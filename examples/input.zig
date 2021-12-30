const std = @import("std");

const termbox = @import("termbox");
const InputSettings = termbox.InputSettings;
const Termbox = termbox.Termbox;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var t = try Termbox.init(allocator);
    defer t.shutdown() catch {};

    try t.selectInputSettings(InputSettings{
        .mode = .Esc,
        .mouse = true,
    });

    var anchor = t.back_buffer.anchor(1, 1);
    try anchor.writer().print("Input testing", .{});

    anchor.move(1, 2);
    try anchor.writer().print("Press q key to quit", .{});

    try t.present();

    main: while (try t.pollEvent()) |ev| {
        switch (ev) {
            .Key => |key_ev| switch (key_ev.ch) {
                'q' => break :main,
                else => {},
            },
            else => {},
        }

        t.clear();
        anchor.move(1, 1);
        try anchor.writer().print("Event: {}", .{ev});
        anchor.move(1, 2);
        try anchor.writer().print("Press q key to quit", .{});

        try t.present();
    }
}
