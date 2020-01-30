const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const File = std.fs.File;

const term = @import("term.zig");

const Key = enum(u16) {
    F1 = 0xFFFF - 0,
    F2 = 0xFFFF - 1,
    F3 = 0xFFFF - 2,
    F4 = 0xFFFF - 3,
    F5 = 0xFFFF - 4,
    F6 = 0xFFFF - 5,
    F7 = 0xFFFF - 6,
    F8 = 0xFFFF - 7,
    F9 = 0xFFFF - 8,
    F10 = 0xFFFF - 9,
    F11 = 0xFFFF - 10,
    F12 = 0xFFFF - 11,
    Insert = 0xFFFF - 12,
    Delete = 0xFFFF - 13,
    Home = 0xFFFF - 14,
    End = 0xFFFF - 15,
    PageUp = 0xFFFF - 16,
    PageDown = 0xFFFF - 17,
    ArrowUp = 0xFFFF - 18,
    ArrowDown = 0xFFFF - 19,
    ArrowLeft = 0xFFFF - 20,
    ArrowRight = 0xFFFF - 21,
    MouseLeft = 0xFFFF - 22,
    MouseRight = 0xFFFF - 23,
    MouseMiddle = 0xFFFF - 24,
    MouseRelease = 0xFFFF - 25,
    MouseWheelUp = 0xFFFF - 26,
    MouseWheelDown = 0xFFFF - 27,
};

const Cell = struct {
    ch : u32,
    fg : u16,
    bg : u16,
};

const Modifier = enum(u8) {
    Alt    = 0x01,
    Motion = 0x02,
};

const Color = enum {
    Default = 0x00,
    Black   = 0x01,
    Red     = 0x02,
    Green   = 0x03,
    Yellow  = 0x04,
    Blue    = 0x05,
    Magenta = 0x06,
    Cyan    = 0x07,
    White   = 0x08,
};

const Attribute = enum {
    Bold      = 0x0100,
    Underline = 0x0200,
    Reverse   = 0x0400,
};

const EventType = enum(u8) {
    Key    = 1,
    Resize = 2,
    Mouse  = 3,
};

const Event = struct {
    type : EventType,
    mod : Modifier,
    key : u16,
    ch : u32,
    w : i32,
    h : i32,
    x : i32,
    y : i32,
};

const InputMode = enum(u3) {
    Current = 0,
    Esc     = 1,
    Alt     = 2,
    Mouse   = 4,
};

const OutputMode = enum {
    Current   = 0,
    Normal    = 1,
    Output256 = 2,
    Output216 = 3,
    Grayscale = 4,
};

const CellBuffer = struct {
    alloc: *Allocator,

    width  : usize,
    height : usize,
    cells  : []Cell,

    const Self = @This();

    fn init(allocator: *Allocator, w: usize, h: usize) !Self {
        return Self {
            .alloc = allocator,
            .width = w,
            .height = h,
            .cells = try allocator.alloc(Cell, w * h),
        };
    }

    fn deinit(self: *Self) void {
        self.alloc.free(self.cells);
    }

    fn resize(self: *Self, w: usize, h: usize) !void {
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
            std.mem.copy(u8, old_buf[src..src + min_w], self.cells[dest..dest + min_w]);
        }

        self.alloc.free(old_buf);
    }

    fn clear(self: *Self) void {
        for (self.cells) |*cell| {
            cell.ch = ' ';
        }
    }
};

fn writeCursor(buffer: ArrayList(u8), x: usize, y: usize) !void {
    var buf: [32]u8 = undefined;
    const options = fmt.FormatOptions{};

    try buffer.appendSlice("\x1b[");
    try buffer.appendSlice(buf[0..std.fmt.formatIntBuf(buf[0..], y + 1, 10, false, options)]);
    try buffer.appendSlice(";");
    try buffer.appendSlice(buf[0..std.fmt.formatIntBuf(buf[0..], x + 1, 10, false, options)]);
    try buffer.appendSlice("H");
}

fn writeSgr(buffer: ArrayList(u8), fg: u16, bg: u16, mode: OutputMode) !void {
    var buf: [32]u8 = undefined;

    switch (mode) {
        .Output256, .Output216, .Grayscale => {},
        else => {},
    }
}

pub const Termbox = struct {
    alloc: *Allocator,

    inout: File,

    back_buffer: CellBuffer,
    front_buffer: CellBuffer,
    output_buffer: ArrayList(u8),
    input_buffer: ArrayList(u8),

    term_w: usize,
    term_h: usize,

    input_mode: InputMode,
    output_mode: OutputMode,

    const Self = @This();

    pub fn initFile(allocator: *Allocator, file: File) !Termbox {
        return Self {
            .alloc = allocator,

            .inout = file,

            .back_buffer = try CellBuffer.init(allocator, 0, 0),
            .front_buffer = try CellBuffer.init(allocator, 0, 0),
            .output_buffer = ArrayList(u8).init(allocator),
            .input_buffer = ArrayList(u8).init(allocator),

            .term_w = 0,
            .term_h = 0,

            .input_mode = InputMode.Esc,
            .output_mode = OutputMode.Normal,
        };
    }

    pub fn initPath(allocator: *Allocator, path: []const u8) !Self {
        return try initFile(allocator, try std.fs.openFileAbsolute(path, .{ .read = true, .write = true }));
    }

    pub fn init(allocator: *Allocator) !Self {
        return try initPath(allocator, "/dev/tty");
    }

    pub fn clear(self: *Self) void {
        self.back_buffer.clear();
    }

    pub fn selectInputMode(self: *Self) void {
    }

    pub fn selectOutputMode(self: *Self) void {
    }

    pub fn shutdown(self: *Self) void {
        self.back_buffer.deinit();
        self.front_buffer.deinit();
        self.output_buffer.deinit();
        self.input_buffer.deinit();
    }

    pub fn present(self: *Self) void {
    }

    fn setCursor(self: *Self, cx: usize, cy: usize) void {
    }
};
