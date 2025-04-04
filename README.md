# zig-termbox

termbox-inspired library for creating terminal user interfaces

Works with Zig 0.14.0.

## Concepts

`termbox` is a *double-buffered* terminal library. This means that
when you call functions to draw on the screen, you are not actually
sending data to the terminal, but instead act on an intermediate data
structure called the *back buffer*. Only when you call
`Termbox.present`, the terminal is actually updated to reflect the
state of the *back buffer*.

An advantage of this design is that repeated calls to
`Termbox.present` only update the parts of the terminal interface that
have actually changed since the last call. `termbox` achieves this by
tracking the current state of the terminal in the internal *front
buffer*.

## Examples

```zig
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
```

Further examples can be found in the `examples` subdirectory.
