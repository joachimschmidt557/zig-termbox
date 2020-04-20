const std = @import("std");

const termbox = @import("src/main.zig");
const Termbox = termbox.Termbox;

pub const io_mode = .evented;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;

    var t = try Termbox.init(allocator);
    defer t.shutdown() catch {};

    for ("Hello World") |ch, i| {
        t.back_buffer.get(i + 1, 1).ch = ch;
    }
    try t.present();
    const ev = try t.pollEvent();
    // std.debug.warn("{}\n", .{ try t.pollEvent() });
}
