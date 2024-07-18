const std = @import("std");
const expect = std.testing.expect;
const test_allocator = std.testing.allocator;
const openDirAbsolute = std.fs.openDirAbsolute;

const nixos_profiles_path = "/nix/var/nix/profiles";
const nixos_booted_system_path = "/run/booted-system";
const nixos_current_system_path = "/run/current-system";

// https://nix.dev/manual/nix/2.22/command-ref/new-cli/nix3-store-diff-closures
// show diffs of all profiles:
// `nix profile diff-closures --profile /nix/var/nix/profiles/system`
//
// https://nix.dev/manual/nix/2.22/command-ref/new-cli/nix3-profile-diff-closures
// diff booted and current (so only useful after an update):
// `nix store diff-closures /run/booted-system /run/current-system`
// compare specific profiles:
// `nix store diff-closures /nix/var/nix/profiles/system-655-link /nix/var/nix/profiles/system-658-link`

pub fn main() !void {
    // stdout is for the actual output of your application
    // stdin, stdout and stderr are data streams that can be treated as files
    const stdout_file_handle = std.io.getStdOut();
    const stdout_writer = stdout_file_handle.writer();

    // batch writes into a buffer for efficiency
    // bufferedWriter is 4096 bytes by default
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


    var profiles_dir = openDirAbsolute(nixos_profiles_path, .{ .iterate = true }) catch |err| {
        std.debug.print("unable to open profiles directory '{s}': {s}\n", .{ nixos_profiles_path, @errorName(err) });
        std.process.exit(1); // exit with error
    };
    defer profiles_dir.close();
    var iter = profiles_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .sym_link) {
            continue; // jump to next iteration
            // break; // break out of loop
        }

        // system -> sym-link to current profile
        // system-{no}-link -> sym-link to /nix/store/{...rest}

        try bw_writer.print("{s}\n", .{entry.name});
    }

    try bw.flush();
    std.debug.print("After dir flush.\n", .{});

    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer gpa.deinit();
    // const allocator = gpa.allocator();

    // get current: /nix/var/nix/profiles/system
    // get newest: /nix/var/nix/profiles/system-{biggest-number}-link
    // get oldest: /nix/var/nix/profiles/system-{smallest-number}-link
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
