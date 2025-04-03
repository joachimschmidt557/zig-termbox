const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const BufferedWriter = std.io.BufferedWriter;
const File = std.fs.File;
const Fifo = std.fifo.LinearFifo(u8, .{ .Static = 512 });
const bufferedWriter = std.io.bufferedWriter;

const wcwidth = @import("wcwidth").wcwidth;

const ansi_term = @import("ansi_term");
const updateStyle = ansi_term.format.updateStyle;
const writeCursor = ansi_term.cursor.setCursor;

pub const Style = ansi_term.style.Style;
pub const Color = ansi_term.style.Color;
pub const ColorRGB = ansi_term.style.ColorRGB;
pub const FontStyle = ansi_term.style.FontStyle;

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

const OutputMode = enum {
    Normal,
    Output256,
    Output216,
    Grayscale,
};

pub const Termbox = struct {
    allocator: Allocator,

    orig_tios: std.posix.termios,

    inout: File,

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

    current_style: Style,

    const Self = @This();

    pub fn initFile(allocator: Allocator, file: File) !Self {
        var self = Self{
            .allocator = allocator,

            .orig_tios = try std.posix.tcgetattr(file.handle),

            .inout = file,

            .back_buffer = undefined,
            .front_buffer = undefined,
            .output_buffer = bufferedWriter(file.writer()),
            .input_buffer = Fifo.init(),

            .term = try term.Term.initTerm(allocator),
            .term_w = 0,
            .term_h = 0,

            .input_settings = .{},
            .output_mode = .Normal,

            .cursor = .Hidden,
            .cursor_state = .{},

            .current_style = .{},
        };

        var tios = self.orig_tios;

        tios.iflag.IGNBRK = false;
        tios.iflag.BRKINT = false;
        tios.iflag.PARMRK = false;
        tios.iflag.ISTRIP = false;
        tios.iflag.INLCR = false;
        tios.iflag.IGNCR = false;
        tios.iflag.ICRNL = false;
        tios.iflag.IXON = false;

        tios.oflag.OPOST = false;

        tios.lflag.ECHO = false;
        tios.lflag.ECHONL = false;
        tios.lflag.ICANON = false;
        tios.lflag.ISIG = false;
        tios.lflag.IEXTEN = false;

        tios.cflag.CSIZE = .CS8;

        // FIXME
        const VMIN = 6;
        const VTIME = 5;
        tios.cc[VMIN] = 0;
        tios.cc[VTIME] = 0;
        try std.posix.tcsetattr(self.inout.handle, std.posix.TCSA.FLUSH, tios);

        try self.output_buffer.writer().writeAll(self.term.funcs.get(.EnterCa));
        try self.output_buffer.writer().writeAll(self.term.funcs.get(.EnterKeypad));
        try self.output_buffer.writer().writeAll(self.term.funcs.get(.HideCursor));
        try self.sendClear();

        self.updateTermSize();
        self.back_buffer = try CellBuffer.init(allocator, self.term_w, self.term_h);
        self.front_buffer = try CellBuffer.init(allocator, self.term_w, self.term_h);
        self.back_buffer.clear(self.current_style);
        self.front_buffer.clear(self.current_style);

        return self;
    }

    pub fn initPath(allocator: Allocator, path: []const u8) !Self {
        return try initFile(allocator, try std.fs.openFileAbsolute(path, .{ .mode = .read_write }));
    }

    pub fn init(allocator: Allocator) !Self {
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
        try std.posix.tcsetattr(self.inout.handle, std.os.linux.TCSA.FLUSH, self.orig_tios);

        self.term.deinit();
        self.inout.close();

        self.back_buffer.deinit();
        self.front_buffer.deinit();
        self.input_buffer.deinit();
    }

    pub fn present(self: *Self) !void {
        self.cursor_state.pos = null;
        var y: usize = 0;
        while (y < self.front_buffer.height) : (y += 1) {
            var x: usize = 0;
            while (x < self.front_buffer.width) {
                const back = self.back_buffer.get(x, y);
                const front = self.front_buffer.get(x, y);
                const wcw = wcwidth(back.ch);
                const w: usize = if (wcw >= 0) @intCast(wcw) else 1;

                if (front.eql(back.*)) {
                    x += w;
                    continue;
                }

                front.* = back.*;

                try updateStyle(self.output_buffer.writer(), back.style, self.current_style);
                self.current_style = back.style;

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
                            .style = back.style,
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
        self.current_style = Style{};
        self.back_buffer.clear(self.current_style);
    }

    pub fn selectInputSettings(self: *Self, input_settings: InputSettings) !void {
        try input_settings.applySettings(self.term, self.output_buffer.writer());
        self.input_settings = input_settings;
    }

    fn updateTermSize(self: *Self) void {
        var sz = std.mem.zeroes(std.posix.winsize);

        _ = std.os.linux.ioctl(self.inout.handle, std.os.linux.T.IOCGWINSZ, @intFromPtr(&sz));

        self.term_w = sz.col;
        self.term_h = sz.row;
    }

    fn sendChar(self: *Self, x: usize, y: usize, c: u21) !void {
        const wanted_pos = Pos{ .x = x, .y = y };
        if (self.cursor_state.pos == null or !std.meta.eql(self.cursor_state.pos, @as(?Pos, wanted_pos))) {
            try writeCursor(self.output_buffer.writer(), x, y);
            self.cursor_state.pos = Pos{ .x = x, .y = y };
        }

        var buf: [7]u8 = undefined;
        const len = std.unicode.utf8Encode(@intCast(c), &buf) catch 0;
        try self.output_buffer.writer().writeAll(buf[0..len]);
    }

    fn sendClear(self: *Self) !void {
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
