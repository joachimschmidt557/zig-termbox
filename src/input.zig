const std = @import("std");
const Buffer = std.ArrayList(u8);
const File = std.fs.File;

const Term = @import("term.zig").Term;

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

    CtrlTilde = 0x00,
    CtrlA = 0x01,
    CtrlB = 0x02,
    CtrlC = 0x03,
    CtrlD = 0x04,
    CtrlE = 0x05,
    CtrlF = 0x06,
    CtrlG = 0x07,
    Backspace = 0x08,
    Tab = 0x09,
    CtrlJ = 0x0A,
    CtrlK = 0x0B,
    CtrlL = 0x0C,
    Enter = 0x0D,
    CtrlN = 0x0E,
    CtrlO = 0x0F,
    CtrlP = 0x10,
    CtrlQ = 0x11,
    CtrlR = 0x12,
    CtrlS = 0x13,
    CtrlT = 0x14,
    CtrlU = 0x15,
    CtrlV = 0x16,
    CtrlW = 0x17,
    CtrlX = 0x18,
    CtrlY = 0x19,
    CtrlZ = 0x1A,
    Esc = 0x1B,
    Ctrl4 = 0x1C,
    Ctrl5 = 0x1D,
    Ctrl6 = 0x1E,
    Ctrl7 = 0x1F,
    Space = 0x20,
    Backspace2 = 0x7F,
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
    action: MouseAction,
    motion: bool,
    x: usize,
    y: usize,
};

pub const Event = union(EventType) {
    Key: KeyEvent,
    Resize: ResizeEvent,
    Mouse: MouseEvent,
};

fn parseMouseEvent(buf: []const u8) ?MouseEvent {
    if (buf.len >= 6 and std.mem.startsWith(u8, buf, "\x1B[M")) {
        // X10 mouse encoding, the simplest one
        // \033 [ M Cb Cx Cy
        const b = buf[3] - 32;
        const action = switch (b & 3) {
            0 => if (b & 64 != 0) MouseAction.MouseWheelUp else MouseAction.MouseLeft,
            1 => if (b & 64 != 0) MouseAction.MouseWheelDown else MouseAction.MouseMiddle,
            2 => MouseAction.MouseRight,
            3 => MouseAction.MouseRelease,
            else => return null,
        };
        const x = @intCast(u8, buf[4] - 1 - 32);
        const y = @intCast(u8, buf[5] - 1 - 32);

        return MouseEvent{
            .action = action,
            .motion = (b & 32) != 0,
            .x = x,
            .y = y,
        };
    } else if (std.mem.startsWith(u8, buf, "\x1B[")) {
        // xterm 1006 extended mode or urxvt 1015 extended mode
        // xterm: \033 [ < Cb ; Cx ; Cy (M or m)
        // urxvt: \033 [ Cb ; Cx ; Cy M
        const is_u = !(buf.len >= 2 and buf[2] == '<');
        const offset = if (is_u) 2 else @as(usize, 3);

        var iter = std.mem.split(buf[offset..], ";");
        const cb = iter.next() orelse return null;
        const cx = iter.next() orelse return null;

        const rest = iter.next() orelse return null;
        const index_m = std.mem.indexOfAny(u8, rest, "mM") orelse return null;
        const cy = rest[0..index_m];
        const is_m = rest[index_m] == 'M';

        const n1 = std.fmt.parseInt(u8, cb, 10) catch |e| std.debug.panic("{}", .{e});
        const n2 = std.fmt.parseInt(u8, cx, 10) catch return null;
        const n3 = std.fmt.parseInt(u8, cy, 10) catch return null;

        const b = if (is_u) n1 - 32 else n1;
        const x = n2 - 1;
        const y = n3 - 1;

        const action = switch (b & 3) {
            0 => if (b & 64 != 0) MouseAction.MouseWheelUp else MouseAction.MouseLeft,
            1 => if (b & 64 != 0) MouseAction.MouseWheelDown else MouseAction.MouseMiddle,
            2 => MouseAction.MouseRight,
            3 => MouseAction.MouseRelease,
            else => return null,
        };

        return MouseEvent{
            .action = action,
            .motion = (b & 32) != 0,
            .x = x,
            .y = y,
        };
    } else {
        return null;
    }
}

fn parseEscapeSequence(buf: []const u8, term: Term) ?Event {
    if (parseMouseEvent(buf)) |x| return Event{ .Mouse = x };

    for (term.keys.data) |k, i| {
        if (std.mem.startsWith(u8, buf, k)) {
            const key_ev = KeyEvent{
                .mod = 0,
                .key = 0xFFFF - @intCast(u16, i),
                .ch = 0,
            };
            return Event{ .Key = key_ev };
        }
    }

    return null;
}

pub fn extractEvent(inbuf: *Buffer, term: Term, settings: InputSettings) ?Event {
    if (inbuf.items.len == 0) return null;

    // Escape
    if (inbuf.items[0] == '\x1B') {
        if (parseEscapeSequence(inbuf.items, term)) |x| {
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
        inbuf.span()[0] == @enumToInt(Key.Backspace2))
    {
        const key_ev = KeyEvent{
            .mod = 0,
            .key = @intCast(u16, inbuf.span()[0]),
            .ch = 0,
        };
        return Event{ .Key = key_ev };
    }

    // UTF-8
    if (std.unicode.utf8ByteSequenceLength(inbuf.items[0])) |utf8_len| {
        if (inbuf.items.len >= utf8_len) {
            const decoded = std.unicode.utf8Decode(inbuf.span()[0..utf8_len]) catch unreachable;
            const key_ev = KeyEvent{
                .mod = 0,
                .key = 0,
                .ch = @intCast(u32, decoded),
            };
            return Event{ .Key = key_ev };
        }
    } else |err| {}

    return null;
}

pub fn waitFillEvent(inout: File, buf: *Buffer, term: Term, settings: InputSettings) !?Event {
    var debug_log = try std.fs.cwd().createFile("debug.log", .{});
    defer debug_log.close();

    while (true) {
        // Read everything we can into the buffer
        var b: [64]u8 = undefined;
        while (true) {
            const amt_read = try inout.readAll(&b);
            try buf.appendSlice(b[0..amt_read]);
            if (amt_read < 64) break;
        }

        _ = try debug_log.writeAll("here\n");

        if (extractEvent(buf, term, settings)) |x| {
            return x;
        } else {
            // Wait for events
            var event = std.os.epoll_event{
                .data = std.os.epoll_data{
                    .@"u32" = 0,
                },
                .events = std.os.EPOLLIN,
            };
            var recieved_events: [1]std.os.epoll_event = undefined;

            const epfd = try std.os.epoll_create1(0);
            try std.os.epoll_ctl(epfd, std.os.EPOLL_CTL_ADD, inout.handle, &event);
            _ = try debug_log.writeAll("waiting\n");
            _ = std.os.epoll_wait(epfd, &recieved_events, -1);
        }
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

    pub fn applySettings(self: Self, term: Term, writer: var) !void {
        if (self.mouse) {
            try writer.writeAll(term.funcs.get(.EnterMouse));
        } else {
            try writer.writeAll(term.funcs.get(.ExitMouse));
        }
    }
};
