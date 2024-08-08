const std = @import("std");
const Allocator = std.mem.Allocator;

const wcwidth = @import("wcwidth").wcwidth;
const Style = @import("ansi-term").style.Style;

pub const Cell = struct {
    ch: u21,
    style: Style,

    const Self = @This();

    pub fn eql(self: Self, other: Self) bool {
        return self.ch == other.ch and self.style.eql(other.style);
    }
};

pub const CellBuffer = struct {
    allocator: Allocator,

    width: usize,
    height: usize,
    cells: []Cell,

    const Self = @This();

    pub fn init(allocator: Allocator, w: usize, h: usize) !Self {
        return Self{
            .allocator = allocator,
            .width = w,
            .height = h,
            .cells = try allocator.alloc(Cell, w * h),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.cells);
    }

    pub fn resize(self: *Self, w: usize, h: usize) !void {
        const old_width = self.width;
        const old_height = self.height;
        const old_buf = self.cells;

        self.width = w;
        self.height = h;
        self.cells = try self.allocator.alloc(Cell, w * h);

        const min_w = if (w < old_width) w else old_width;
        const min_h = if (h < old_height) h else old_height;

        var i: usize = 0;
        while (i < min_h) : (i += 1) {
            const src = i * old_width;
            const dest = i * w;
            std.mem.copy(u8, old_buf[src .. src + min_w], self.cells[dest .. dest + min_w]);
        }

        self.allocator.free(old_buf);
    }

    pub fn clear(self: *Self, style: Style) void {
        for (self.cells) |*cell| {
            cell.ch = ' ';
            cell.style = style;
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
                context.pos += @intCast(wcwidth(c));
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
