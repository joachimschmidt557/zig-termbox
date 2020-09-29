const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const BufferedWriter = std.io.BufferedWriter;
const File = std.fs.File;
const Fifo = std.fifo.LinearFifo(u8, .{ .Static = 512 });
const bufferedWriter = std.io.bufferedWriter;

const ioctl = @cImport({
    @cInclude("sys/ioctl.h");
});

const wcwidth = @import("zig-wcwidth/src/main.zig").wcwidth;
const writeCursor = @import("zig-ansi-term/src/cursor.zig").setCursor;

const term = @import("term.zig");
const cellbuffer = @import("cellbuffer.zig");
pub const Cell = cellbuffer.Cell;
pub const CellBuffer = cellbuffer.CellBuffer;

const cursor = @import("cursor.zig");
pub const Pos = cursor.Pos;
pub const CursorState = cursor.CursorState;
pub const Cursor = cursor.Cursor;

const input = @import("input.zig");
pub const Event = input.Event;
pub const InputSettings = input.InputSettings;

const style = @import("style.zig");
pub const Color = style.Color;
pub const Attribute = style.Attribute;

const OutputMode = enum {
    Normal,
    Output256,
    Output216,
    Grayscale,
};

fn writeSgr(writer: anytype, fg: u16, bg: u16, mode: OutputMode) !void {
    if (fg == @enumToInt(Color.Default) and bg == @enumToInt(Color.Default))
        return;

    switch (mode) {
        .Output256, .Output216, .Grayscale => {
            try writer.writeAll("\x1B[");
            if (fg != @enumToInt(Color.Default)) {
                try writer.print("38;5;{}", .{fg});
                if (bg != @enumToInt(Color.Default)) {
                    try writer.writeAll(";");
                }
            }
            if (bg != @enumToInt(Color.Default)) {
                try writer.print("48;5;{}", .{bg});
            }
            try writer.writeAll("m");
        },
        .Normal => {
            try writer.writeAll("\x1B[");
            if (fg != @enumToInt(Color.Default)) {
                try writer.print("3{}", .{fg - 1});
                if (bg != @enumToInt(Color.Default)) {
                    try writer.writeAll(";");
                }
            }
            if (bg != @enumToInt(Color.Default)) {
                try writer.print("4{}", .{bg - 1});
            }
            try writer.writeAll("m");
        },
    }
}

pub const Termbox = struct {
    alloc: *Allocator,

    orig_tios: std.os.termios,

    inout: File,
    winch_fds: [2]std.os.fd_t,

    back_buffer: CellBuffer,
    front_buffer: CellBuffer,
    output_buffer: BufferedWriter(4096, File.Writer),
    input_buffer: Fifo,

    term: term.Term,
    term_w: usize,
    term_h: usize,

    input_settings: InputSettings,
    output_mode: OutputMode,

    cursor: Cursor,
    cursor_state: CursorState,

    foreground: u16,
    background: u16,
    last_fg: u16,
    last_bg: u16,

    const Self = @This();

    pub fn initFile(allocator: *Allocator, file: File) !Self {
        var self = Self{
            .alloc = allocator,

            .orig_tios = try std.os.tcgetattr(file.handle),

            .inout = file,
            .winch_fds = try std.os.pipe(),

            .back_buffer = undefined,
            .front_buffer = undefined,
            .output_buffer = bufferedWriter(file.writer()),
            .input_buffer = Fifo.init(),

            .term = try term.Term.initTerm(allocator),
            .term_w = 0,
            .term_h = 0,

            .input_settings = InputSettings.default,
            .output_mode = OutputMode.Normal,

            .cursor = Cursor.Hidden,
            .cursor_state = CursorState.default,

            .foreground = @enumToInt(Color.Default),
            .background = @enumToInt(Color.Default),
            .last_fg = 0xFFFF,
            .last_bg = 0xFFFF,
        };

        var tios = self.orig_tios;
        const tcflag_t = std.os.tcflag_t;

        tios.iflag &= ~(@intCast(tcflag_t, std.os.IGNBRK) | @intCast(tcflag_t, std.os.BRKINT) |
            @intCast(tcflag_t, std.os.PARMRK) | @intCast(tcflag_t, std.os.ISTRIP) |
            @intCast(tcflag_t, std.os.INLCR) | @intCast(tcflag_t, std.os.IGNCR) |
            @intCast(tcflag_t, std.os.ICRNL) | @intCast(tcflag_t, std.os.IXON));
        tios.oflag &= ~(@intCast(tcflag_t, std.os.OPOST));
        tios.lflag &= ~(@intCast(tcflag_t, std.os.ECHO) | @intCast(tcflag_t, std.os.ECHONL) |
            @intCast(tcflag_t, std.os.ICANON) | @intCast(tcflag_t, std.os.ISIG) |
            @intCast(tcflag_t, std.os.IEXTEN));
        tios.cflag &= ~(@intCast(tcflag_t, std.os.CSIZE) | @intCast(tcflag_t, std.os.PARENB));
        tios.cflag |= @intCast(tcflag_t, std.os.CS8);
        // FIXME
        const VMIN = 6;
        const VTIME = 5;
        tios.cc[VMIN] = 0;
        tios.cc[VTIME] = 0;
        try std.os.tcsetattr(self.inout.handle, std.os.TCSA.FLUSH, tios);

        try self.output_buffer.writer().writeAll(self.term.funcs.get(.EnterCa));
        try self.output_buffer.writer().writeAll(self.term.funcs.get(.EnterKeypad));
        try self.output_buffer.writer().writeAll(self.term.funcs.get(.HideCursor));
        try self.sendClear();

        self.updateTermSize();
        self.back_buffer = try CellBuffer.init(allocator, self.term_w, self.term_h);
        self.front_buffer = try CellBuffer.init(allocator, self.term_w, self.term_h);
        self.back_buffer.clear(self.foreground, self.background);
        self.front_buffer.clear(self.foreground, self.background);

        return self;
    }

    pub fn initPath(allocator: *Allocator, path: []const u8) !Self {
        return try initFile(allocator, try std.fs.openFileAbsolute(path, .{ .read = true, .write = true }));
    }

    pub fn init(allocator: *Allocator) !Self {
        return try initPath(allocator, "/dev/tty");
    }

    pub fn shutdown(self: *Self) !void {
        const writer = self.output_buffer.writer();

        try writer.writeAll(self.term.funcs.get(.ShowCursor));
        try writer.writeAll(self.term.funcs.get(.Sgr0));
        try writer.writeAll(self.term.funcs.get(.ClearScreen));
        try writer.writeAll(self.term.funcs.get(.ExitCa));
        try writer.writeAll(self.term.funcs.get(.ExitKeypad));
        try writer.writeAll(self.term.funcs.get(.ExitMouse));
        try self.output_buffer.flush();
        try std.os.tcsetattr(self.inout.handle, std.os.TCSA.FLUSH, self.orig_tios);

        self.term.deinit();
        self.inout.close();
        std.os.close(self.winch_fds[0]);
        std.os.close(self.winch_fds[1]);

        self.back_buffer.deinit();
        self.front_buffer.deinit();
        self.input_buffer.deinit();
    }

    pub fn present(self: *Self) !void {
        var y: usize = 0;
        while (y < self.front_buffer.height) : (y += 1) {
            var x: usize = 0;
            while (x < self.front_buffer.width) {
                const back = self.back_buffer.get(x, y);
                const front = self.front_buffer.get(x, y);
                const wcw = wcwidth(back.ch);
                const w = if (wcw >= 0) @intCast(usize, wcw) else 1;

                if (front.eql(back.*)) {
                    x += w;
                    continue;
                }

                front.* = back.*;
                try self.sendAttr(back.fg, back.bg);
                if (x + w >= self.front_buffer.width) {
                    var i = x;
                    while (i < self.front_buffer.width) : (i += 1) {
                        try self.sendChar(i, y, ' ');
                    }
                } else {
                    try self.sendChar(x, y, back.ch);
                    var i = x + 1;
                    while (i < x + w) : (i += 1) {
                        self.front_buffer.get(i, y).* = Cell{
                            .ch = 0,
                            .fg = back.fg,
                            .bg = back.bg,
                        };
                    }
                }

                x += w;
            }
        }
        switch (self.cursor) {
            .Visible => |pos| try writeCursor(self.output_buffer.writer(), pos.x, pos.y),
            else => {},
        }
        try self.output_buffer.flush();
    }

    pub fn setCursor(self: *Self, new: Cursor) !void {
        const writer = self.output_buffer.writer();

        switch (new) {
            .Hidden => {
                if (self.cursor == .Visible) {
                    try writer.writeAll(self.term.funcs.get(.HideCursor));
                }
            },
            .Visible => |pos| {
                if (self.cursor == .Hidden) {
                    try writer.writeAll(self.term.funcs.get(.ShowCursor));
                }
                try writeCursor(writer, pos.x, pos.y);
                self.cursor_state.pos = pos;
            },
        }

        self.cursor = new;
    }

    pub fn pollEvent(self: *Self) !?Event {
        return try input.waitFillEvent(self.inout, &self.input_buffer, self.term, self.input_settings);
    }

    pub fn clear(self: *Self) void {
        self.back_buffer.clear(self.foreground, self.background);
    }

    pub fn selectInputSettings(self: *Self, input_settings: InputSettings) !void {
        try input_settings.applySettings(self.term, self.output_buffer.writer());
        self.input_settings = input_settings;
    }

    fn updateTermSize(self: *Self) void {
        var sz = std.mem.zeroes(ioctl.winsize);

        _ = ioctl.ioctl(self.inout.handle, ioctl.TIOCGWINSZ, &sz);

        self.term_w = sz.ws_col;
        self.term_h = sz.ws_row;
    }

    fn sendAttr(self: *Self, fg: u16, bg: u16) !void {
        const writer = self.output_buffer.writer();

        if (self.last_fg != fg or self.last_bg != bg) {
            try writer.writeAll(self.term.funcs.get(.Sgr0));

            const fgcol = switch (self.output_mode) {
                .Output256 => fg & 0xFF,
                .Output216 => (if ((fg & 0xFF) <= 215) (fg & 0xFF) else 7) + 0x10,
                .Grayscale => (if ((fg & 0xFF) <= 23) (fg & 0xFF) else 23) + 0xe8,
                .Normal => fg & 0x0F,
            };

            const bgcol = switch (self.output_mode) {
                .Output256 => bg & 0xFF,
                .Output216 => (if ((bg & 0xFF) <= 215) (bg & 0xFF) else 0) + 0x10,
                .Grayscale => (if ((bg & 0xFF) <= 23) (bg & 0xFF) else 0) + 0xe8,
                .Normal => bg & 0x0F,
            };

            if (fg & @enumToInt(Attribute.Bold) > 0) {
                try writer.writeAll(self.term.funcs.get(.Bold));
            }
            if (bg & @enumToInt(Attribute.Bold) > 0) {
                try writer.writeAll(self.term.funcs.get(.Blink));
            }
            if (fg & @enumToInt(Attribute.Underline) > 0) {
                try writer.writeAll(self.term.funcs.get(.Underline));
            }
            if (fg & @enumToInt(Attribute.Reverse) > 0 or bg & @enumToInt(Attribute.Reverse) > 0) {
                try writer.writeAll(self.term.funcs.get(.Reverse));
            }

            try writeSgr(writer, fgcol, bgcol, self.output_mode);

            self.last_fg = fg;
            self.last_bg = bg;
        }
    }

    fn sendChar(self: *Self, x: usize, y: usize, c: u21) !void {
        const wanted_pos = Pos{ .x = x, .y = y };
        if (!self.cursor_state.pos.eql(wanted_pos)) {
            try writeCursor(self.output_buffer.writer(), x, y);
            self.cursor_state.pos = wanted_pos;
        }

        var buf: [7]u8 = undefined;
        const len = std.unicode.utf8Encode(@intCast(u21, c), &buf) catch 0;
        try self.output_buffer.writer().writeAll(buf[0..len]);
    }

    fn sendClear(self: *Self) !void {
        try self.sendAttr(self.foreground, self.background);
        try self.output_buffer.writer().writeAll(self.term.funcs.get(.ClearScreen));
        try self.output_buffer.flush();
    }

    fn updateSize(self: *Self) !void {
        self.updateTermSize();
        self.back_buffer.resize(self.term_w, self.term_h);
        self.front_buffer.resize(self.term_w, self.term_h);
        self.front_buffer.clear();
        try self.sendClear();
    }
};
