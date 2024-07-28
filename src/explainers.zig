const std = @import("std");
const expect = std.testing.expect;
const test_allocator = std.testing.allocator;

export fn add(a: i32, b: i32) i32 {
    return a + b;
}
test "basic add functionality" {
    try expect(add(3, 7) == 10);
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
