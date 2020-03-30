const std = @import("std");
const Buffer = std.Buffer;
const File = std.fs.File;

pub const Key = enum(u16) {
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

    CtrlTilde       = 0x00,
    CtrlA           = 0x01,
    CtrlB           = 0x02,
    CtrlC           = 0x03,
    CtrlD           = 0x04,
    CtrlE           = 0x05,
    CtrlF           = 0x06,
    CtrlG           = 0x07,
    Backspace        = 0x08,
    Tab              = 0x09,
    CtrlJ           = 0x0A,
    CtrlK           = 0x0B,
    CtrlL           = 0x0C,
    Enter            = 0x0D,
    CtrlN           = 0x0E,
    CtrlO           = 0x0F,
    CtrlP           = 0x10,
    CtrlQ           = 0x11,
    CtrlR           = 0x12,
    CtrlS           = 0x13,
    CtrlT           = 0x14,
    CtrlU           = 0x15,
    CtrlV           = 0x16,
    CtrlW           = 0x17,
    CtrlX           = 0x18,
    CtrlY           = 0x19,
    CtrlZ           = 0x1A,
    Esc              = 0x1B,
    Ctrl4           = 0x1C,
    Ctrl5           = 0x1D,
    Ctrl6           = 0x1E,
    Ctrl7           = 0x1F,
    Space            = 0x20,
    Backspace2       = 0x7F,
};

pub const Modifier = enum(u8) {
    Alt = 0x01,
    Motion = 0x02,
};

pub const EventType = enum {
    Key,
    Resize,
    Mouse,
};

pub const KeyEvent = struct {
    mod: u8,
    key: u16,
    ch: u32,
};

pub const ResizeEvent = struct {
    w: i32,
    h: i32,
};

pub const MouseAction = enum {
    MouseLeft,
    MouseRight,
    MouseMiddle,
    MouseRelease,
    MouseWheelUp,
    MouseWheelDown,
};

pub const MouseEvent = struct {
    a: MouseAction,
    x: i32,
    y: i32,
};

pub const Event = union (EventType) {
    Key: KeyEvent,
    Resize: ResizeEvent,
    Mouse: MouseEvent,
};

fn parseMouseEvent(buf: []const u8) ?MouseEvent {
    if (buf.len >= 6 and std.mem.startsWith(u8, buf, "\x1B[M")) {
        const b = buf[3] - 32;
        const action = switch (b & 3) {
            0 => MouseAction.MouseWheelUp,
            1 => MouseAction.MouseWheelDown,
            2 => MouseAction.MouseRight,
            3 => MouseAction.MouseRelease,
            else => return null,
        };
        const x = @intCast(u8, buf[4] - 1 - 32);
        const y = @intCast(u8, buf[5] - 1 - 32);

        return MouseEvent{
            .a = action,
            .x = x,
            .y = y,
        };
    } else if (std.mem.startsWith(u8, buf, "\x1B[")) {
        return null;
    } else {
        return null;
    }
}

fn parseEscapeSequence(buf: []const u8) ?Event {
    if (parseMouseEvent(buf)) |x| return Event{ .Mouse = x };



    return null;
}

pub fn extractEvent(inbuf: *Buffer, settings: InputSettings) ?Event {
    if (inbuf.len() == 0) return null;

    // Escape
    if (inbuf.span()[0] == '\x1B') {
        if (parseEscapeSequence(inbuf.span())) |x| {
            return x;
        } else {
            switch (settings.mode) {
                .Esc => {
                    const key_ev = KeyEvent{
                        .mod = 0,
                        .key = @enumToInt(Key.Esc),
                        .ch = 0,
                    };
                    return Event{ .Key = key_ev };
                },
                .Alt => {},
            }
        }
    }

    // Functional key
    if (inbuf.span()[0] <= @enumToInt(Key.Space) or
            inbuf.span()[0] == @enumToInt(Key.Backspace2)) {
        const key_ev = KeyEvent{
            .mod = 0,
            .key = std.mem.bytesToValue(u16, inbuf.span()[0..2]),
            .ch = 0,
        };
        return Event{ .Key = key_ev };
    }

    // UTF-8
    if (std.unicode.utf8ByteSequenceLength(inbuf.span()[0])) |utf8_len| {
        if (inbuf.len() >= utf8_len) {
            const key_ev = KeyEvent{
                .mod = 0,
                .key = 0,
                .ch = @intCast(u32, std.unicode.utf8Decode(inbuf.span()[0..utf8_len]) catch unreachable),
            };
            return Event{ .Key = key_ev };
        }
    } else |_| {}

    return null;
}

fn readUpTo(inout: File, buf: *Buffer, n: usize) !usize {
    const prev_len = buf.len();
    try buf.resize(prev_len + n);
    
    var read_n: usize = 0;
    while (read_n <= n) {
        if (read_n < n) {
            const r = try inout.read(buf.span()[prev_len + read_n..prev_len + n]);
            if (r == 0) break;
            read_n += r;
        }
    }

    try buf.resize(prev_len + read_n);
    return read_n;
}

pub fn waitFillEvent(inout: File, buf: *Buffer, settings: InputSettings, timeout: usize) !?Event {
    if (extractEvent(buf, settings)) |x| return x;

    const enough_data_for_parsing = 64;
    const n = try readUpTo(inout, buf, enough_data_for_parsing);
    if (n > 0) {
        if (extractEvent(buf, settings)) |x| return x;
    }

    return null;
}

pub const InputMode = enum {
    Esc,
    Alt,
};

pub const InputSettings = struct {
    mode: InputMode,
    mouse: bool,

    const Self = @This();

    pub const default = Self{
        .mode = InputMode.Esc,
        .mouse = false,
    };
};