const std = @import("std");
const expect = std.testing.expect;

const nix_profiles_path = "/nix/var/nix/profiles";

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
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // stdout is for the actual output of your application
    // stdin, stdout and stderr are data streams that can be treated as files
    const stdout_file_handle = std.io.getStdOut();
    const stdout_writer = stdout_file_handle.writer();

    // batch writes into a buffer for efficiency
    // bufferedWriter is 4096 bytes by default
    // https://ziglang.org/documentation/0.13.0/std/#src/std/io/buffered_writer.zig
    var bw = std.io.bufferedWriter(stdout_writer);
    const bw_writer = bw.writer();

    // print(format, args) calls std.fmt.format for placeholder substitutions
    // https://ziglang.org/documentation/0.13.0/std/#std.io.Writer.print
    // https://ziglang.org/documentation/0.13.0/std/#std.fmt.format
    // format text and add it to buffer
    try bw_writer.print("Run `zig build test` to run the tests.\n", .{});

    // write buffer contents to file using writeAll(), which is a straight copy of bytes
    // https://ziglang.org/documentation/0.13.0/std/#src/std/io/buffered_writer.zig
    try bw.flush();

    std.debug.print("After flush.\n", .{});


test "always succeeds" {
    try expect(true);
}

// test "always fails" {
//     try expect(false);
// }

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
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
