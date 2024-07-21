const std = @import("std");
const expect = std.testing.expect;
const test_allocator = std.testing.allocator;
const openDirAbsolute = std.fs.openDirAbsolute;

const nixos_profiles_path = "/nix/var/nix/profiles";
// current: `/nix/var/nix/profiles/system`
// newest: `/nix/var/nix/profiles/system-{biggest-number}-link`
// oldest: `/nix/var/nix/profiles/system-{smallest-number}-link`
// `system` -> sym-link to current profile
// `system-{number}-link` -> sym-link to `/nix/store/{...rest}`
const profile_trim_left = "system-";
const profile_trim_right = "-link";

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

    // u8 range: 0-255
    // u16 range: 0-65535
    // u32 range: 0-4294967295
    // u64 range: 0-18446744073709551615
    var profile_newest: u16 = 0;
    var profile_oldest: u16 = 65535;

    var iter = profiles_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .sym_link) {
            continue; // jump to next iteration
            // break; // break out of loop
        }

        var created = entry.name;
        // try bw_writer.print("entry.name: {s}\n", .{created});

        if (!std.mem.startsWith(u8, created, profile_trim_left)) continue;
        if (!std.mem.endsWith(u8, created, profile_trim_right)) continue;

        created = std.mem.trimLeft(u8, created, profile_trim_left);
        created = std.mem.trimRight(u8, created, profile_trim_right);
        // try bw_writer.print("trimmed string: {s}\n", .{created});

        const created_int = try std.fmt.parseUnsigned(u16, created, 10); // base 10
        // try bw_writer.print("parsed uint: {d}\n", .{created_int});

        if (created_int > profile_newest) {
            profile_newest = created_int;
        } else if (created_int < profile_oldest) {
            profile_oldest = created_int;
        }
    }

    try bw_writer.print("oldest profile: {d}\n", .{profile_oldest});
    try bw_writer.print("newest profile: {d}\n", .{profile_newest});

    try bw.flush();
    // std.debug.print("After flush.\n", .{});

    try execute_process();
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
fn execute_process() !void {
    // the command to run
    const argv = [_][]const u8{ "ls", "./" };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // init a child process
    var proc = std.process.Child.init(&argv, allocator);
    try proc.spawn();

    // clean up
    // the process only ends after this call returns
    // const term = try proc.wait();
    const terminated_state = try proc.wait();
    _ = terminated_state;

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
