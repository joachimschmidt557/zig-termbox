const std = @import("std");

pub const Pos = struct {
    x: usize,
    y: usize,
};

pub const Cursor = union(enum) {
    Hidden,
    Visible: Pos,
};

pub const CursorState = struct {
    hidden: bool = false,
    pos: Pos = Pos{ .x = 0, .y = 0 },
};
