const std = @import("std");

const termbox = @import("src/main.zig");
const Termbox = termbox.Termbox;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;

    var t = try Termbox.init(allocator);

    var input_settings = t.input_settings;
    input_settings.mouse = true;
    try t.selectInputSettings(input_settings);

    const writer = t.back_buffer.writer(1, 1);
    try writer.print("Hello World!", .{});
    try t.present();

    // try t.setCursor(.{ .Visible = .{ .x = 10, .y = 10 } });
    // try t.present();

    const ev = try t.pollEvent();

    t.shutdown() catch {};

    std.debug.warn("{}\n", .{ev});
}
