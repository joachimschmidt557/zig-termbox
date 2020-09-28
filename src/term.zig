const std = @import("std");
const Allocator = std.mem.Allocator;

const terminfo = @import("terminfo.zig");

const enter_mouse_seq = "\x1b[?1000h\x1b[?1002h\x1b[?1015h\x1b[?1006h";
const exit_mouse_seq = "\x1b[?1006l\x1b[?1015l\x1b[?1002l\x1b[?1000l";

const ti_magic = 0432;
const ti_alt_magic = 542;
const ti_header_length = 12;

const ti_funcs = [_]i16{
    28, 40, 16, 13, 5, 39, 36, 27, 26, 34, 89, 88,
};
const ti_keys = [_]i16{
    66, 68, 69, 70, 71, 72, 73, 74, 75, 67, 216, 217, 77, 59, 76, 164, 82, 81,
    87, 61, 79, 83,
};

const t_keys_num = 22;
const t_funcs_num = 14;

pub const TermFunc = enum {
    EnterCa,
    ExitCa,
    ShowCursor,
    HideCursor,
    ClearScreen,
    Sgr0,
    Underline,
    Bold,
    Blink,
    Reverse,
    EnterKeypad,
    ExitKeypad,
    EnterMouse,
    ExitMouse,
};

pub const TermFuncs = struct {
    allocator: ?*Allocator,
    data: [t_funcs_num][]const u8,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        if (self.allocator) |a| {
            for (self.data) |x| a.free(x);
        }
    }

    pub fn get(self: Self, x: TermFunc) []const u8 {
        return self.data[@enumToInt(x)];
    }
};

pub const TermKeys = struct {
    allocator: ?*Allocator,
    data: [t_keys_num][]const u8,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        if (self.allocator) |a| {
            for (self.data) |x| a.free(x);
        }
    }
};

pub const Term = struct {
    name: []const u8,
    keys: TermKeys,
    funcs: TermFuncs,

    const Self = @This();

    fn tryCompatible(term: []const u8, name: []const u8, keys: TermKeys, funcs: TermFuncs) ?Self {
        if (std.mem.indexOf(u8, term, name)) |_| {
            return Self{
                .name = name,
                .keys = keys,
                .funcs = funcs,
            };
        } else {
            return null;
        }
    }

    fn initTermBuiltin() !Self {
        const term = std.os.getenv("TERM") orelse return error.UnsupportedTerm;

        for (terms) |t| {
            if (std.mem.eql(u8, term, t.name)) return t;
        }

        // Trying some heuristics
        if (Self.tryCompatible(term, "xterm", xterm_keys, xterm_funcs)) |r| return r;
        if (Self.tryCompatible(term, "rxvt", rxvt_unicode_keys, rxvt_unicode_funcs)) |r| return r;
        if (Self.tryCompatible(term, "linux", linux_keys, linux_funcs)) |r| return r;
        if (Self.tryCompatible(term, "Eterm", eterm_keys, eterm_funcs)) |r| return r;
        if (Self.tryCompatible(term, "screen", screen_keys, screen_funcs)) |r| return r;
        if (Self.tryCompatible(term, "cygwin", xterm_keys, xterm_funcs)) |r| return r;

        return error.UnsupportedTerm;
    }

    pub fn initTerm(allocator: *Allocator) !Self {
        const data = (try terminfo.loadTerminfo(allocator)) orelse return initTermBuiltin();
        defer allocator.free(data);

        var result: Self = Self{
            .name = "",
            .keys = TermKeys{
                .allocator = allocator,
                .data = undefined,
            },
            .funcs = TermFuncs{
                .allocator = allocator,
                .data = undefined,
            },
        };

        const header_0 = std.mem.readIntNative(i16, data[0..2]);
        const header_1 = std.mem.readIntNative(i16, data[2..4]);
        var header_2 = std.mem.readIntNative(i16, data[4..6]);
        const header_3 = std.mem.readIntNative(i16, data[6..8]);
        const header_4 = std.mem.readIntNative(i16, data[8..10]);
        const number_sec_len = if (header_0 == ti_alt_magic) @as(i16, 4) else 2;

        if (@mod(header_1 + header_2, 2) != 0) {
            header_2 += 1;
        }

        const str_offset = ti_header_length + header_1 + header_2 + number_sec_len * header_3;
        const table_offset = str_offset + 2 * header_4;

        // Keys
        for (result.keys.data) |*x, i| {
            x.* = try terminfo.copyString(allocator, data, str_offset + 2 * ti_keys[i], table_offset);
        }

        // Functions
        for (result.funcs.data[0 .. t_funcs_num - 2]) |*x, i| {
            x.* = try terminfo.copyString(allocator, data, str_offset + 2 * ti_funcs[i], table_offset);
        }
        result.funcs.data[t_funcs_num - 2] = try allocator.dupe(u8, enter_mouse_seq);
        result.funcs.data[t_funcs_num - 1] = try allocator.dupe(u8, exit_mouse_seq);

        return result;
    }

    pub fn deinit(self: *Self) void {
        self.keys.deinit();
        self.funcs.deinit();
    }
};

const rxvt_256color_keys = TermKeys{
    .allocator = null,
    .data = [_][]const u8{
        "\x1B[11~", "\x1B[12~", "\x1B[13~", "\x1B[14~", "\x1B[15~", "\x1B[17~",
        "\x1B[18~", "\x1B[19~", "\x1B[20~", "\x1B[21~", "\x1B[23~", "\x1B[24~",
        "\x1B[2~",  "\x1B[3~",  "\x1B[7~",  "\x1B[8~",  "\x1B[5~",  "\x1B[6~",
        "\x1B[A",   "\x1B[B",   "\x1B[D",   "\x1B[C",
    },
};
const rxvt_256color_funcs = TermFuncs{
    .allocator = null,
    .data = [_][]const u8{
        "\x1B7\x1B[?47h", "\x1B[2J\x1B[?47l\x1B8",
        "\x1B[?25h",      "\x1B[?25l",
        "\x1B[H\x1B[2J",  "\x1B[m",
        "\x1B[4m",        "\x1B[1m",
        "\x1B[5m",        "\x1B[7m",
        "\x1B=",          "\x1B>",
        enter_mouse_seq,  exit_mouse_seq,
    },
};

const eterm_keys = TermKeys{
    .allocator = null,
    .data = [_][]const u8{
        "\x1B[11~", "\x1B[12~", "\x1B[13~", "\x1B[14~", "\x1B[15~", "\x1B[17~",
        "\x1B[18~", "\x1B[19~", "\x1B[20~", "\x1B[21~", "\x1B[23~", "\x1B[24~",
        "\x1B[2~",  "\x1B[3~",  "\x1B[7~",  "\x1B[8~",  "\x1B[5~",  "\x1B[6~",
        "\x1B[A",   "\x1B[B",   "\x1B[D",   "\x1B[C",
    },
};
const eterm_funcs = TermFuncs{
    .allocator = null,
    .data = [_][]const u8{
        "\x1B7\x1B[?47h", "\x1B[2J\x1B[?47l\x1B8", "\x1B[?25h", "\x1B[?25l",
        "\x1B[H\x1B[2J",  "\x1B[m",                "\x1B[4m",   "\x1B[1m",
        "\x1B[5m",        "\x1B[7m",               "",          "",
        "",               "",
    },
};

const screen_keys = TermKeys{
    .allocator = null,
    .data = [_][]const u8{
        "\x1BOP",   "\x1BOQ",   "\x1BOR",   "\x1BOS",   "\x1B[15~", "\x1B[17~",
        "\x1B[18~", "\x1B[19~", "\x1B[20~", "\x1B[21~", "\x1B[23~", "\x1B[24~",
        "\x1B[2~",  "\x1B[3~",  "\x1B[1~",  "\x1B[4~",  "\x1B[5~",  "\x1B[6~",
        "\x1BOA",   "\x1BOB",   "\x1BOD",   "\x1BOC",
    },
};
const screen_funcs = TermFuncs{
    .allocator = null,
    .data = [_][]const u8{
        "\x1B[?1049h",   "\x1B[?1049l",  "\x1B[34h\x1B[?25h", "\x1B[?25l",
        "\x1B[H\x1B[J",  "\x1B[m",       "\x1B[4m",           "\x1B[1m",
        "\x1B[5m",       "\x1B[7m",      "\x1B[?1h\x1B=",     "\x1B[?1l\x1B>",
        enter_mouse_seq, exit_mouse_seq,
    },
};

const rxvt_unicode_keys = TermKeys{
    .allocator = null,
    .data = [_][]const u8{
        "\x1B[11~", "\x1B[12~", "\x1B[13~", "\x1B[14~", "\x1B[15~", "\x1B[17~",
        "\x1B[18~", "\x1B[19~", "\x1B[20~", "\x1B[21~", "\x1B[23~", "\x1B[24~",
        "\x1B[2~",  "\x1B[3~",  "\x1B[7~",  "\x1B[8~",  "\x1B[5~",  "\x1B[6~",
        "\x1B[A",   "\x1B[B",   "\x1B[D",   "\x1B[C",
    },
};
const rxvt_unicode_funcs = TermFuncs{
    .allocator = null,
    .data = [_][]const u8{
        "\x1B[?1049h",   "\x1B[r\x1B[?1049l", "\x1B[?25h", "\x1B[?25l",
        "\x1B[H\x1B[2J", "\x1B[m\x1B(B",      "\x1B[4m",   "\x1B[1m",
        "\x1B[5m",       "\x1B[7m",           "\x1B=",     "\x1B>",
        enter_mouse_seq, exit_mouse_seq,
    },
};

const linux_keys = TermKeys{
    .allocator = null,
    .data = [_][]const u8{
        "\x1B[[A",  "\x1B[[B",  "\x1B[[C",  "\x1B[[D",  "\x1B[[E",  "\x1B[17~",
        "\x1B[18~", "\x1B[19~", "\x1B[20~", "\x1B[21~", "\x1B[23~", "\x1B[24~",
        "\x1B[2~",  "\x1B[3~",  "\x1B[1~",  "\x1B[4~",  "\x1B[5~",  "\x1B[6~",
        "\x1B[A",   "\x1B[B",   "\x1B[D",   "\x1B[C",
    },
};
const linux_funcs = TermFuncs{
    .allocator = null,
    .data = [_][]const u8{
        "",           "",        "\x1B[?25h\x1B[?0c", "\x1B[?25l\x1B[?1c", "\x1B[H\x1B[J",
        "\x1B[0;10m", "\x1B[4m", "\x1B[1m",           "\x1B[5m",           "\x1B[7m",
        "",           "",        "",                  "",
    },
};

const xterm_keys = TermKeys{
    .allocator = null,
    .data = [_][]const u8{
        "\x1BOP",   "\x1BOQ",   "\x1BOR",   "\x1BOS",   "\x1B[15~", "\x1B[17~", "\x1B[18~",
        "\x1B[19~", "\x1B[20~", "\x1B[21~", "\x1B[23~", "\x1B[24~", "\x1B[2~",  "\x1B[3~",
        "\x1BOH",   "\x1BOF",   "\x1B[5~",  "\x1B[6~",  "\x1BOA",   "\x1BOB",   "\x1BOD",
        "\x1BOC",
    },
};
const xterm_funcs = TermFuncs{
    .allocator = null,
    .data = [_][]const u8{
        "\x1B[?1049h",   "\x1B[?1049l",  "\x1B[?12l\x1B[?25h", "\x1B[?25l",
        "\x1B[H\x1B[2J", "\x1B(B\x1B[m", "\x1B[4m",            "\x1B[1m",
        "\x1B[5m",       "\x1B[7m",      "\x1B[?1h\x1B=",      "\x1B[?1l\x1B>",
        enter_mouse_seq, exit_mouse_seq,
    },
};

const terms = [_]Term{
    .{ .name = "rxvt-256color", .keys = rxvt_256color_keys, .funcs = rxvt_256color_funcs },
    .{ .name = "Eterm", .keys = eterm_keys, .funcs = eterm_funcs },
    .{ .name = "screen", .keys = screen_keys, .funcs = screen_funcs },
    .{ .name = "rxvt-unicode", .keys = rxvt_unicode_keys, .funcs = rxvt_unicode_funcs },
    .{ .name = "linux", .keys = linux_keys, .funcs = linux_funcs },
    .{ .name = "xterm", .keys = xterm_keys, .funcs = xterm_funcs },
};
