const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Buffer = ArrayList(u8);
const BufferedOutStream = std.io.BufferedOutStream;
const File = std.fs.File;
const bufferedOutStream = std.io.bufferedOutStream;

const ioctl = @cImport({ @cInclude("sys/ioctl.h"); });

const wcwidth = @import("../wcwidth/src/main.zig").wcwidth;

const term = @import("term.zig");
const cellbuffer = @import("cellbuffer.zig");
const Cell = cellbuffer.Cell;
const CellBuffer = cellbuffer.CellBuffer;
const cursor = @import("cursor.zig");
const Cursor = cursor.Cursor;
const input = @import("input.zig");
const Event = input.Event;
const InputSettings = input.InputSettings;

const Color = enum(u16) {
    Default = 0x00,
    Black = 0x01,
    Red = 0x02,
    Green = 0x03,
    Yellow = 0x04,
    Blue = 0x05,
    Magenta = 0x06,
    Cyan = 0x07,
    White = 0x08,
};

const Attribute = enum(u16) {
    Bold = 0x0100,
    Underline = 0x0200,
    Reverse = 0x0400,
};

const OutputMode = enum {
    Current = 0,
    Normal = 1,
    Output256 = 2,
    Output216 = 3,
    Grayscale = 4,
};

fn writeSgr(out_stream: var, fg: u16, bg: u16, mode: OutputMode) !void {
    if (fg == @enumToInt(Color.Default) and bg == @enumToInt(Color.Default))
        return;

    switch (mode) {
        .Output256, .Output216, .Grayscale => {
            try out_stream.writeAll("\x1B[");
            if (fg != @enumToInt(Color.Default)) {
                try out_stream.print("38;5;{}", .{ fg });
                if (bg != @enumToInt(Color.Default)) {
                    try out_stream.writeAll(";");
                }
            }
            if (bg != @enumToInt(Color.Default)) {
                try out_stream.print("48;5;{}", .{ bg });
            }
            try out_stream.writeAll("m");
        },
        .Normal, .Current => {
            try out_stream.writeAll("\x1B[");
            if (fg != @enumToInt(Color.Default)) {
                try out_stream.print("3{}", .{ fg - 1 });
                if (bg != @enumToInt(Color.Default)) {
                    try out_stream.writeAll(";");
                }
            }
            if (bg != @enumToInt(Color.Default)) {
                try out_stream.print("4{}", .{ bg - 1 });
            }
            try out_stream.writeAll("m");
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
    output_buffer: BufferedOutStream(4096, File.OutStream),
    input_buffer: Buffer,

    term: term.Term,
    term_w: usize,
    term_h: usize,

    input_settings: InputSettings,
    output_mode: OutputMode,

    cur: Cursor,

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
            .output_buffer = bufferedOutStream(file.outStream()),
            .input_buffer = Buffer.init(allocator),

            .term = try term.Term.initTerm(allocator),
            .term_w = 0,
            .term_h = 0,

            .input_settings = InputSettings.default,
            .output_mode = OutputMode.Normal,

            .cur = Cursor.Hidden,

            .foreground = @enumToInt(Color.Default),
            .background = @enumToInt(Color.Default),
            .last_fg = 0xFFFF,
            .last_bg = 0xFFFF,
        };

        var tios = self.orig_tios;
        const tcflag_t = std.os.tcflag_t;

        tios.iflag &= ~(@as(tcflag_t, std.os.IGNBRK) | @as(tcflag_t, std.os.BRKINT) |
                            @as(tcflag_t, std.os.PARMRK) | @as(tcflag_t, std.os.ISTRIP) |
                            @as(tcflag_t, std.os.INLCR) | @as(tcflag_t, std.os.IGNCR) |
                            @as(tcflag_t, std.os.ICRNL) | @as(tcflag_t, std.os.IXON));
        tios.oflag &= ~(@as(tcflag_t, std.os.OPOST));
        tios.lflag &= ~(@as(tcflag_t, std.os.ECHO) | @as(tcflag_t, std.os.ECHONL) |
                            @as(tcflag_t, std.os.ICANON) | @as(tcflag_t, std.os.ISIG) |
                            @as(tcflag_t, std.os.IEXTEN));
        tios.cflag &= ~(@as(tcflag_t, std.os.CSIZE) | @as(tcflag_t, std.os.PARENB));
        tios.cflag |= @as(tcflag_t, std.os.CS8);
        // FIXME
        // tios.cc[std.os.VMIN] = 0;
        // tios.cc[std.os.VTIME] = 0;
        try std.os.tcsetattr(self.inout.handle, std.os.TCSA.FLUSH, tios);

        try self.output_buffer.outStream().writeAll(self.term.funcs.get(.EnterCa));
        try self.output_buffer.outStream().writeAll(self.term.funcs.get(.EnterKeypad));
        try self.output_buffer.outStream().writeAll(self.term.funcs.get(.HideCursor));
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
        const out_stream = self.output_buffer.outStream();

        try out_stream.writeAll(self.term.funcs.get(.ShowCursor));
        try out_stream.writeAll(self.term.funcs.get(.Sgr0));
        try out_stream.writeAll(self.term.funcs.get(.ClearScreen));
        try out_stream.writeAll(self.term.funcs.get(.ExitCa));
        try out_stream.writeAll(self.term.funcs.get(.ExitKeypad));
        try out_stream.writeAll(self.term.funcs.get(.ExitMouse));
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
        // Invalidate cursor position to kickstart drawing
        self.cur = Cursor.Hidden;

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
        switch (self.cur) {
            .Visible => |pos| try cursor.writeCursor(self.output_buffer.outStream(), pos),
            else => {},
        }
        try self.output_buffer.flush();
    }

    fn setCursor(self: *Self, new: Cursor) !void {
        switch (new) {
            .Hidden => {
                if (self.cur == .Visible) {
                    try self.output_buffer.append(self.term.funcs.hide_cusor);
                }
            },
            .Visible => |pos| {
                if (self.cur == .Hidden) {
                    try self.output_buffer.append(self.term.funcs.show_cursor);
                }
                try cursor.writeCursor(&self.output_buffer, pos);
            },
        }

        self.cur = new;
    }

    pub fn pollEvent(self: *Self) !?Event {
        return try input.waitFillEvent(self.inout, &self.input_buffer, self.term, self.input_settings);
    }

    pub fn clear(self: *Self) void {
        self.back_buffer.clear(self.foreground, self.background);
    }

    fn updateTermSize(self: *Self) void {
        var sz = std.mem.zeroes(ioctl.winsize);

        _ = ioctl.ioctl(self.inout.handle, ioctl.TIOCGWINSZ, &sz);

        self.term_w = sz.ws_col;
        self.term_h = sz.ws_row;
    }

    fn sendAttr(self: *Self, fg: u16, bg: u16) !void {
        const out_stream = self.output_buffer.outStream();

        if (self.last_fg != fg and self.last_bg != bg) {
            try out_stream.writeAll(self.term.funcs.get(.Sgr0));

            const fgcol = switch (self.output_mode) {
                .Output256 => fg & 0xFF,
                .Output216 => (if ((fg & 0xFF) <= 215) (fg & 0xFF) else 7) + 0x10,
                .Grayscale => (if ((fg & 0xFF) <= 23) (fg & 0xFF) else 23) + 0xe8,
                .Normal, .Current => fg & 0x0F,
            };

            const bgcol = switch (self.output_mode) {
                .Output256 => bg & 0xFF,
                .Output216 => (if ((bg & 0xFF) <= 215) (bg & 0xFF) else 0) + 0x10,
                .Grayscale => (if ((bg & 0xFF) <= 23) (bg & 0xFF) else 0) + 0xe8,
                .Normal, .Current => bg & 0x0F,
            };

            if (fg & @enumToInt(Attribute.Bold) > 0) {
                try out_stream.writeAll(self.term.funcs.get(.Bold));
            }
            if (bg & @enumToInt(Attribute.Bold) > 0) {
                try out_stream.writeAll(self.term.funcs.get(.Blink));
            }
            if (fg & @enumToInt(Attribute.Underline) > 0) {
                try out_stream.writeAll(self.term.funcs.get(.Underline));
            }
            if (fg & @enumToInt(Attribute.Reverse) > 0 or bg & @enumToInt(Attribute.Reverse) > 0) {
                try out_stream.writeAll(self.term.funcs.get(.Reverse));
            }

            try writeSgr(out_stream, fgcol, bgcol, self.output_mode);

            self.last_fg = fg;
            self.last_bg = bg;
        }
    }

    fn sendChar(self: *Self, x: usize, y: usize, c: u32) !void {
        const wanted_cur = Cursor{ .Visible = cursor.Pos{ .x = x, .y = y } };
        if (!self.cur.eql(wanted_cur)) {
            try cursor.writeCursor(self.output_buffer.outStream(), cursor.Pos{ .x = x, .y = y });
        }
        self.cur = wanted_cur;

        var buf: [7]u8 = undefined;
        const len = std.unicode.utf8Encode(@intCast(u21, c), &buf) catch 0;
        try self.output_buffer.outStream().writeAll(buf[0..len]);
    }

    fn sendClear(self: *Self) !void {
        try self.sendAttr(self.foreground, self.background);
        try self.output_buffer.outStream().writeAll(self.term.funcs.get(.ClearScreen));
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
