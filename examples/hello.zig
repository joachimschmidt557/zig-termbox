const std = @import("std");

const termbox = @import("termbox");
const Termbox = termbox.Termbox;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var t = try Termbox.init(allocator);
    defer t.shutdown() catch {};

    var anchor = t.back_buffer.anchor(1, 1);
    try anchor.writer().print("Hello {s}!", .{"World"});

    anchor.move(1, 2);
    try anchor.writer().print("Press any key to quit", .{});

    try t.present();

    _ = try t.pollEvent();
}
