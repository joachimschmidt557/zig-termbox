const std = @import("std");

const termbox = @import("src/main.zig");
const Termbox = termbox.Termbox;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;

    var t = try Termbox.init(allocator);
    defer t.shutdown() catch {};

    for ("Hello World") |ch, i| {
        t.back_buffer.get(i + 1, 1).ch = ch;
    }
    try t.present();
    _ = try t.pollEvent();
    std.time.sleep(1000000000);

    t.clear();
    try t.present();
    std.time.sleep(1000000000);
}
