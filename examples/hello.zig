const std = @import("std");

const termbox = @import("termbox");
const Termbox = termbox.Termbox;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;

    var t = try Termbox.init(allocator);
    defer t.shutdown() catch {};

    var anchor_hello = t.back_buffer.anchor(1, 1);
    try anchor_hello.writer().print("Hello {}!", .{"World"});

    var anchor_quit = t.back_buffer.anchor(1, 2);
    try anchor_quit.writer().print("Press any key to quit", .{});

    try t.present();

    _ = try t.pollEvent();
}
