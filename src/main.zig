const std = @import("std");
const expect = std.testing.expect;
const test_allocator = std.testing.allocator;
const openDirAbsolute = std.fs.openDirAbsolute;
// const fatal = std.zig.fatal;

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
}

test "simple test" {
    var list = std.ArrayList(i32).init(test_allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

// https://zig.guide/getting-started/running-tests/
test "always succeeds" {
    try expect(true);
}
// test "always fails" {
//     try expect(false);
// }

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

fn explain_strings() !void {
    // a string is a slice of bytes
    // 1 byte = 8 bits, so type is u8 - unsigned 8-bit integer
    var hi: []const u8 = "hi";
    hi = "hi!";
    std.debug.print("Type of string: {}\n", .{@TypeOf(hi)}); // []const u8
    // slice of const u8

    // String literals are constant single-item pointers to null-terminated byte arrays
    // null-terminated (a.k.a sentinel-terminated) means it ends with zero
    // standard practice in C is for character arrays to mark the end of the array with a zero character
    std.debug.print("Type of string literal: {}\n", .{@TypeOf("hello there")}); // *const [11:0]u8
    // const single-item pointer to array of u8s, with length 11, with sentinel 0
    const hello = "Hello";
    std.debug.print("Type of string literal: {}\n", .{@TypeOf(hello)}); // *const [5:0]u8
    // const single-item pointer to array of u8s, with length 5, with sentinel 0

    // Unicode code point literals use single quotes
    const ziguana = '🦎';
    std.debug.print("Type of ziguana: {}\n", .{@TypeOf(ziguana)}); // comptime_int, same as integer literals

    // print unicode
    std.debug.print("{u} Zig! {u}\n", .{ ziguana, '⚡' });
}

fn explain_printing() !void {
    // stdin, stdout and stderr are data streams that can be treated as files
    const stdout_file_handle = std.io.getStdOut();
    const stdout_writer = stdout_file_handle.writer();

    // batch writes into a buffer for efficiency
    // bufferedWriter is 4096 bytes (4 kB) by default
    // https://ziglang.org/documentation/0.13.0/std/#src/std/io/buffered_writer.zig
    var bw = std.io.bufferedWriter(stdout_writer);
    const bw_writer = bw.writer();

    // format text and add it to the buffer
    // print(format, args) calls std.fmt.format for placeholder substitutions
    // https://ziglang.org/documentation/0.13.0/std/#std.io.Writer.print
    // https://ziglang.org/documentation/0.13.0/std/#std.fmt.format
    try bw_writer.print("{s}\n", .{"Print into buffer."});

    // prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("{s} flush.\n", .{"Before"});

    // write buffer contents to file using writeAll(), which is a straight copy of bytes
    // https://ziglang.org/documentation/0.13.0/std/#src/std/io/buffered_writer.zig
    try bw.flush();

    std.debug.print("{s} flush.\n", .{"After"});
}
