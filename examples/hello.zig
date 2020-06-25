const std = @import("std");

const termbox = @import("termbox");
const Termbox = termbox.Termbox;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;

    var t = try Termbox.init(allocator);
    defer t.shutdown() catch {};

    const writer_hello = t.back_buffer.writer(1, 1);
    try writer_hello.print("Hello World!", .{});

    const writer_quit = t.back_buffer.writer(1, 2);
    try writer_quit.print("Press any key to quit", .{});

    try t.present();

    _ = try t.pollEvent();
}
