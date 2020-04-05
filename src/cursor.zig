const std = @import("std");

pub fn writeCursor(out_stream: var, pos: Pos) !void {
    try out_stream.print("\x1B[{};{}H", .{ pos.y + 1, pos.x + 1 });
}

pub const Pos = struct {
    x: usize,
    y: usize,

    const Self = @This();

    pub fn eql(self: Self, other: Self) bool {
        return self.x == other.x and self.y == other.y;
    }
};

pub const CursorState = enum {
    Hidden,
    Visible,
};

pub const Cursor = union(CursorState) {
    Hidden,
    Visible: Pos,

    const Self = @This();
    
    pub fn eql(self: Self, other: Self) bool {
        return switch (self) {
            .Hidden => other == .Hidden,
            .Visible => |self_pos| switch (other) {
                .Hidden => false,
                .Visible => |other_pos| self_pos.eql(other_pos),
            }
        };
    }
};
