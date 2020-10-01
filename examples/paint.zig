const std = @import("std");

const termbox = @import("termbox");
const InputSettings = termbox.InputSettings;
const Termbox = termbox.Termbox;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = &arena.allocator;

    var t = try Termbox.init(allocator);
    defer t.shutdown() catch {};

    try t.selectInputSettings(InputSettings{
        .mode = .Esc,
        .mouse = true,
    });

    var anchor = t.back_buffer.anchor(1, 1);
    try anchor.writer().print("Press any key to quit", .{});
    try t.present();

    var current_color: u8 = 0;
    main: while (try t.pollEvent()) |ev| {
        switch (ev) {
            .Key => break :main,
            .Mouse => |mouse_ev| t.back_buffer.get(mouse_ev.x, mouse_ev.y).style.background = .{ .Fixed = current_color },
            else => continue,
        }
        current_color +%= 1;
        try t.present();
    }
}
