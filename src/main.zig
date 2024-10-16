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
// const nixos_booted_system_path = "/run/booted-system";
// const nixos_current_system_path = "/run/current-system";

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
    \\  pkgs                List all installed packages
;

pub fn main() !void {
    // for printing to stdout
    const stdout_file_handle = std.io.getStdOut();
    const stdout_writer = stdout_file_handle.writer();

    // buffer to flush to stdout
    var bw = std.io.bufferedWriter(stdout_writer);
    const bw_writer = bw.writer();

    // u8  range: 0 to 255
    // u16 range: 0 to 65535
    // u32 range: 0 to 4294967295
    // u64 range: 0 to 18446744073709551615
    var profile_newest: u16 = 0;
    var profile_oldest: u16 = 65535;

    // open profiles dir
    var dir_profiles = openDirAbsolute(nixos_profiles_path, .{ .iterate = true }) catch |err| {
        std.debug.print("unable to open profiles directory '{s}': {s}\n", .{ nixos_profiles_path, @errorName(err) });
        std.process.exit(1); // exit with error
    };
    defer dir_profiles.close();

    var iter = dir_profiles.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .sym_link) continue; // jump to next iteration of loop
        // break; // break out of loop

        // if dir name does not contain a number, go to next dir
        const gen_no = parseGenNoFromProfilePath(entry.name) catch continue;

        if (gen_no > profile_newest) {
            profile_newest = gen_no;
        } else if (gen_no < profile_oldest) {
            profile_oldest = gen_no;
        }
    }

    try bw_writer.print("oldest gen: {d}\n", .{profile_oldest});
    try bw_writer.print("newest gen: {d}\n", .{profile_newest});

    // get current, booted profiles
    var buf_current_profile: [40]u8 = undefined;
    const slice_current_profile = try dir_profiles.readLink("system", &buf_current_profile);
    const profile_current = try parseGenNoFromProfilePath(slice_current_profile);

    try bw_writer.print("current gen: {d}\n", .{profile_current});

    var dir_run = try openDirAbsolute("/run", .{});
    defer dir_run.close();

    var buf_booted_store: [100]u8 = undefined;
    var buf_current_store: [100]u8 = undefined;
    const slice_booted_store = try dir_run.readLink("booted-system", &buf_booted_store);
    const slice_current_store = try dir_run.readLink("current-system", &buf_current_store);

    try bw_writer.print("booted store: {s}\n", .{slice_booted_store});
    try bw_writer.print("current store: {s}\n", .{slice_current_store});

    if (std.mem.eql(u8, slice_booted_store, slice_current_store)) {
        try bw_writer.print("booted same as current\n", .{});
    } else {
        try bw_writer.print("booted different from current\n", .{});
    }
    // TODO figure out profile numbers of booted and current (compare creation times?)

    try bw.flush();

    try diffBootedCurrent();
    // try diffProfilesAll();
    try diffProfiles(profile_newest - 1, profile_newest);
}

// https://zig.guide/standard-library/filesystem/
test "make dir, make files, read files from dir" {
    // make dir
    try std.fs.cwd().makeDir("test-tmp");

    // open dir
    var iter_dir = try std.fs.cwd().openDir(
        "test-tmp",
        .{ .iterate = true },
    );
    defer {
        iter_dir.close();
        std.fs.cwd().deleteTree("test-tmp") catch unreachable;
    }

    // make files in dir
    _ = try iter_dir.createFile("x", .{});
    _ = try iter_dir.createFile("y", .{});
    _ = try iter_dir.createFile("z", .{});

    // count files in dir
    var file_count: usize = 0;
    var iter = iter_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file) file_count += 1;
    }

    // check expected count against actual count
    try expect(file_count == 3);
}

/// Parse profile path "system-{generation_number}-link" and return generation_number.
fn parseGenNoFromProfilePath(dir_path: []const u8) !u16 {
    // check if valid path
    if (!std.mem.startsWith(u8, dir_path, profile_trim_left)) return error.InvalidProfilePath;
    if (!std.mem.endsWith(u8, dir_path, profile_trim_right)) return error.InvalidProfilePath;

    // trim path
    var dir_path_trimmed = dir_path;
    dir_path_trimmed = std.mem.trimLeft(u8, dir_path_trimmed, profile_trim_left);
    dir_path_trimmed = std.mem.trimRight(u8, dir_path_trimmed, profile_trim_right);

    // parse trimmed string as integer (base 10)
    const generation_no = try std.fmt.parseUnsigned(u16, dir_path_trimmed, 10);

    return generation_no;
}
test "parse generation number from profile path" {
    const number: u16 = try parseGenNoFromProfilePath("system-100-link");
    try expect(number == 100);
}
test "throw error if wrong path" {
    try expectError(error.InvalidProfilePath, parseGenNoFromProfilePath("some-random-path"));
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

    // `run` spawns a child process, waits for it, collecting stdout and stderr, and then returns.
    // If it succeeds, the caller owns result.stdout and result.stderr memory.
    // const proc = try std.process.Child.run(.{
    //     .allocator = allocator,
    //     .argv = &argv,
    // });
    // returns `RunResult` on success, which has term, stdout, stderr
    // const term = proc.term;
    // defer allocator.free(proc.stdout);
    // defer allocator.free(proc.stderr);
    //
    // `term` is the terminated state of the child process
    // term can be .Exited, .Signal, .Stopped, .Unknown
    // try std.testing.expectEqual(term, std.process.Child.Term{ .Exited = 0 });

    // Blocks until child process terminates and then cleans up all resources.
    const terminated_state = try proc.wait();
    std.debug.print("diffBootedCurrent terminated state: {any}\n", .{terminated_state});
}

/// Print diff between two profile closures, given their generation numbers.
fn diffProfiles(profile1: u16, profile2: u16) !void {
    // parse paths
    //
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

    // construct shell command
    const argv = [_][]const u8{ "nix", "store", "diff-closures", profile_path1, profile_path2 };

    // allocate memory for shell command
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const allocator = gpa.allocator();

    // run shell command
    var proc = std.process.Child.init(&argv, allocator);
    try proc.spawn();

    // clean up shell command
    const terminated_state = try proc.wait();
    std.debug.print("diffProfiles terminated state: {any}\n", .{terminated_state});
}

/// Print diffs between each generation of profile closure.
fn diffProfilesAll() !void {
    const argv = [_][]const u8{ "nix", "profile", "diff-closures", "--profile", "/nix/var/nix/profiles/system" };

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const allocator = gpa.allocator();

    var proc = std.process.Child.init(&argv, allocator);
    try proc.spawn();

    const terminated_state = try proc.wait();
    std.debug.print("diffProfilesAll terminated state: {any}\n", .{terminated_state});
}
