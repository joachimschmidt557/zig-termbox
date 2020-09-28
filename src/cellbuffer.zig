const std = @import("std");
const Allocator = std.mem.Allocator;

const wcwidth = @import("zig-wcwidth/src/main.zig").wcwidth;

pub const Cell = struct {
    ch: u21,
    fg: u16,
    bg: u16,

    const Self = @This();

    pub fn eql(self: Self, other: Self) bool {
        return self.ch == other.ch and self.fg == other.fg and self.bg == other.bg;
    }
};

pub const CellBuffer = struct {
    alloc: *Allocator,

    width: usize,
    height: usize,
    cells: []Cell,

    const Self = @This();

    pub fn init(allocator: *Allocator, w: usize, h: usize) !Self {
        return Self{
            .alloc = allocator,
            .width = w,
            .height = h,
            .cells = try allocator.alloc(Cell, w * h),
        };
    }

    pub fn deinit(self: *Self) void {
        self.alloc.free(self.cells);
    }

    pub fn resize(self: *Self, w: usize, h: usize) !void {
        const old_width = self.width;
        const old_height = self.height;
        const old_buf = self.cells;

        self.width = w;
        self.height = h;
        self.cells = try allocator.alloc(Cell, w * h);

        const min_w = if (w < old_width) w else old_width;
        const min_h = if (h < old_height) h else old_height;

        var i: usize = 0;
        while (i < min_h) : (i += 1) {
            const src = i * old_width;
            const dest = i * w;
            std.mem.copy(u8, old_buf[src .. src + min_w], self.cells[dest .. dest + min_w]);
        }

        self.alloc.free(old_buf);
    }

    pub fn clear(self: *Self, fg: u16, bg: u16) void {
        for (self.cells) |*cell| {
            cell.ch = ' ';
            cell.fg = fg;
            cell.bg = bg;
        }
    }

    pub fn get(self: *Self, x: usize, y: usize) *Cell {
        return &self.cells[y * self.width + x];
    }

    pub const Anchor = struct {
        cell_buffer: *Self,
        pos: usize,

        const Error = error{InvalidUtf8};

        pub fn write(context: *Anchor, bytes: []const u8) Error!usize {
            const utf8_view = try std.unicode.Utf8View.init(bytes);

            var iter = utf8_view.iterator();
            while (iter.nextCodepoint()) |c| {
                context.cell_buffer.cells[context.pos].ch = c;
                context.pos += @intCast(usize, wcwidth(c));
            }

            return bytes.len;
        }

        pub fn move(self: *Anchor, x: usize, y: usize) void {
            self.pos = y * self.cell_buffer.width + x;
        }

        pub fn writer(self: *Anchor) std.io.Writer(*Anchor, Anchor.Error, Anchor.write) {
            return .{ .context = self };
        }
    };

    pub fn anchor(self: *Self, x: usize, y: usize) Anchor {
        return Anchor{
            .cell_buffer = self,
            .pos = y * self.width + x,
        };
    }
};
