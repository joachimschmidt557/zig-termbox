const std = @import("std");

const enter_mouse_seq = "\x1b[?1000h\x1b[?1002h\x1b[?1015h\x1b[?1006h";
const exit_mouse_seq = "\x1b[?1006l\x1b[?1015l\x1b[?1002l\x1b[?1000l";

pub const TermFuncs = struct {
    enter_ca: []const u8,
    exit_ca: []const u8,
    show_cursor: []const u8,
    hide_cursor: []const u8,
    clear_screen: []const u8,
    sgr0: []const u8,
    underline: []const u8,
    bold: []const u8,
    blink: []const u8,
    reverse: []const u8,
    enter_keypad: []const u8,
    exit_keypad: []const u8,
    enter_mouse: []const u8,
    exit_mouse: []const u8,
};

pub const TermKeys = struct {

};

pub const Term = struct {
    name: []const u8,
    keys: TermKeys,
    funcs: TermFuncs,
};

const rxvt_256color_keys = TermKeys{};
const rxvt_256color_funcs = TermFuncs{
    .enter_ca = "",
    .exit_ca = "",
    .show_cursor = "",
    .hide_cursor = "",
    .clear_screen = "",
    .sgr0 = "",
    .underline = "",
    .bold = "",
    .blink = "",
    .reverse = "",
    .enter_keypad = "",
    .exit_keypad = "",
    .enter_mouse = enter_mouse_seq,
    .exit_mouse = exit_mouse_seq,
};

const terms = [_]Term{
    .{ "rxvt-256color", rxvt_256color_keys, rxvt256color_funcs },
    .{ "Eterm", eterm_keys, eterm_funcs },
    .{ "linux", linux_keys, linux_funcs },
    .{ "xterm", xterm_keys, xterm_funcs }
};
