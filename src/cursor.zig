const std = @import("std");

pub const Pos = struct {
    x: usize,
    y: usize,

    const Self = @This();

    pub fn eql(self: Self, other: Self) bool {
        return self.x == other.x and self.y == other.y;
    }
};

pub const Visibility = enum {
    Hidden,
    Visible,
};

pub const Cursor = union(Visibility) {
    Hidden,
    Visible: Pos,

    const Self = @This();

    pub fn eql(self: Self, other: Self) bool {
        return switch (self) {
            .Hidden => other == .Hidden,
            .Visible => |self_pos| switch (other) {
                .Hidden => false,
                .Visible => |other_pos| self_pos.eql(other_pos),
            },
        };
    }
};

pub const CursorState = struct {
    hidden: bool,
    pos: Pos,

    const Self = @This();

    pub const default = Self{
        .hidden = false,
        .pos = Pos{ .x = 0, .y = 0 },
    };
};
