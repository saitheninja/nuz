const std = @import("std");
const expect = std.testing.expect;
const expectError = std.testing.expectError;
const test_allocator = std.testing.allocator;
const openDirAbsolute = std.fs.openDirAbsolute;

// current: `/nix/var/nix/profiles/system`
// newest: `/nix/var/nix/profiles/system-{biggest-number}-link`
// oldest: `/nix/var/nix/profiles/system-{smallest-number}-link`
// `system` -> sym-link to current profile
// `system-{number}-link` -> sym-link to `/nix/store/{...rest}`
const nixos_profiles_path = "/nix/var/nix/profiles/";
const nixos_profiles_current_path = nixos_profiles_path ++ "system";
const profile_trim_left = "system-";
const profile_trim_right = "-link";

// sym-links to `/nix/store/{...rest}`
const nixos_booted_system_path = "/run/booted-system";
const nixos_current_system_path = "/run/current-system";

// https://nix.dev/manual/nix/2.22/command-ref/new-cli/nix3-profile-diff-closures
// show diffs of all profiles:
// `nix profile diff-closures --profile /nix/var/nix/profiles/system`

// https://nix.dev/manual/nix/2.22/command-ref/new-cli/nix3-store-diff-closures
// diff booted and current (so only useful after an update):
// `nix store diff-closures /run/booted-system /run/current-system`
// compare specific profiles:
// `nix store diff-closures /nix/var/nix/profiles/system-655-link /nix/var/nix/profiles/system-658-link`

const usage =
    \\
    \\Usage: nuz [command] [options]
    \\
    \\Commands:
    \\
    \\  help, -h, --help    Print this help and exit
    \\
    \\  diff                Diff closures of oldest -> newest, booted -> current
    \\  diff -b, --boot     Diff closures of booted -> current
    \\  diff --old=[number] --new=[number]  Diff closures of oldest -> newest
    \\
;

pub fn main() !void {
    const stdout_file_handle = std.io.getStdOut();
    const stdout_writer = stdout_file_handle.writer();

    var bw = std.io.bufferedWriter(stdout_writer);
    const bw_writer = bw.writer();

    var profiles_dir = openDirAbsolute(nixos_profiles_path, .{ .iterate = true }) catch |err| {
        std.debug.print("unable to open profiles directory '{s}': {s}\n", .{ nixos_profiles_path, @errorName(err) });
        std.process.exit(1); // exit with error
    };
    defer profiles_dir.close();

    // u8  range: 0 to 255
    // u16 range: 0 to 65535
    // u32 range: 0 to 4294967295
    // u64 range: 0 to 18446744073709551615
    var profile_newest: u16 = 0;
    var profile_oldest: u16 = 65535;

    var iter = profiles_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .sym_link) continue;
        // continue; // jump to next iteration
        // break; // break out of loop

        const gen_no = parseGenNoFromProfilePath(entry.name) catch continue;
        if (gen_no > profile_newest) {
            profile_newest = gen_no;
        } else if (gen_no < profile_oldest) {
            profile_oldest = gen_no;
        }
    }

    try bw_writer.print("oldest gen: {d}\n", .{profile_oldest});
    try bw_writer.print("newest gen: {d}\n", .{profile_newest});

    var buf: [40]u8 = undefined;
    const buf_current = try profiles_dir.readLink("system", &buf);
    const profile_current = try parseGenNoFromProfilePath(buf_current);

    try bw_writer.print("current gen: {d}\n", .{profile_current});
    try bw.flush();

    try diffBootedCurrent();
    try diffProfiles(profile_oldest, profile_newest);
}

// https://zig.guide/standard-library/filesystem/
test "make dir and read files" {
    try std.fs.cwd().makeDir("test-tmp");
    var iter_dir = try std.fs.cwd().openDir(
        "test-tmp",
        .{ .iterate = true },
    );
    defer {
        iter_dir.close();
        std.fs.cwd().deleteTree("test-tmp") catch unreachable;
    }

    _ = try iter_dir.createFile("x", .{});
    _ = try iter_dir.createFile("y", .{});
    _ = try iter_dir.createFile("z", .{});

    var file_count: usize = 0;
    var iter = iter_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file) file_count += 1;
    }

    try expect(file_count == 3);
}

// https://renatoathaydes.github.io/zig-common-tasks/
/// Print diff of booted profile closure with current profile closure.
fn diffBootedCurrent() !void {
    // argument vector, i.e. the command to run
    // const argv = [_][]const u8{ "ls", "./" };
    // const argv = [_][]const u8{ "nix", "profile", "diff-closures", "--profile", "/nix/var/nix/profiles/system" };
    const argv = [_][]const u8{ "nix", "store", "diff-closures", "/run/booted-system", "/run/current-system" };

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const allocator = gpa.allocator();

    // start a child process
    var proc = std.process.Child.init(&argv, allocator);
    try proc.spawn();

    // clean up
    // the process only ends after this call returns
    const terminated_state = try proc.wait();
    std.debug.print("terminated state: {any}\n", .{terminated_state});

    // term can be .Exited, .Signal, .Stopped, .Unknown
    // try std.testing.expectEqual(term, std.process.Child.Term{ .Exited = 0 });

    // const proc = try std.process.Child.run(.{
    //     .allocator = alloc,
    //     .argv = &argv,
    // });

    // consume stdout and stderr into allocated memory
    // on success, we own the output streams
    // defer alloc.free(proc.stdout);
    // defer alloc.free(proc.stderr);
    //
    // const term = proc.term;
}

/// Print diff of two profile closures, given their generation numbers.
fn diffProfiles(profile1: u16, profile2: u16) !void {
    // nixos_profiles_path, // 22 bytes
    // profile_trim_left, // 7 bytes
    // profile2, // 1 to 5 bytes (u16 range: 0 to 65535)
    // profile_trim_right, // 5 bytes
    // total 39 bytes
    var buf1: [40]u8 = undefined;
    var buf2: [40]u8 = undefined;
    const profile_path1 = try std.fmt.bufPrint(&buf1, "{s}{s}{d}{s}", .{
        nixos_profiles_path,
        profile_trim_left,
        profile1,
        profile_trim_right,
    });
    const profile_path2 = try std.fmt.bufPrint(&buf2, "{s}{s}{d}{s}", .{
        nixos_profiles_path,
        profile_trim_left,
        profile2,
        profile_trim_right,
    });
    // std.debug.print("buf1: {s}\n", .{buf1});
    // std.debug.print("buf2: {s}\n", .{buf2});
    // std.debug.print("path1: {s}\n", .{profile_path1});
    // std.debug.print("path2: {s}\n", .{profile_path2});

    const argv = [_][]const u8{ "nix", "store", "diff-closures", profile_path1, profile_path2 };

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const allocator = gpa.allocator();

    var proc = std.process.Child.init(&argv, allocator);
    try proc.spawn();

    const terminated_state = try proc.wait();
    std.debug.print("terminated state: {any}\n", .{terminated_state});
}

/// Parse profile path "system-{generation_number}-link" and return generation_number.
fn parseGenNoFromProfilePath(dir_path: []const u8) !u16 {
    if (!std.mem.startsWith(u8, dir_path, profile_trim_left)) return error.InvalidProfilePath;
    if (!std.mem.endsWith(u8, dir_path, profile_trim_right)) return error.InvalidProfilePath;

    var dir_path_trimmed = dir_path;
    dir_path_trimmed = std.mem.trimLeft(u8, dir_path_trimmed, profile_trim_left);
    dir_path_trimmed = std.mem.trimRight(u8, dir_path_trimmed, profile_trim_right);

    const generation_no = try std.fmt.parseUnsigned(u16, dir_path_trimmed, 10); // base 10
    return generation_no;
}
test "parse generation number from profile path" {
    const number: u16 = try parseGenNoFromProfilePath("system-100-link");
    try expect(number == 100);
}
test "throw error if wrong path" {
    try expectError(error.InvalidProfilePath, parseGenNoFromProfilePath("some-random-path"));
}
