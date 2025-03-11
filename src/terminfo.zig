const std = @import("std");
const Allocator = std.mem.Allocator;

fn tryPath(alloc: Allocator, path: []const u8, term: []const u8) ?[]const u8 {
    const tmp = std.fmt.allocPrint(alloc, "{s}/{s}/{s}", .{ path, &[_]u8{term[0]}, term }) catch return null;
    defer alloc.free(tmp);

    return std.fs.cwd().readFileAlloc(alloc, tmp, std.math.maxInt(usize)) catch null;
}

pub fn loadTerminfo(alloc: Allocator) !?[]const u8 {
    const term = std.posix.getenv("TERM") orelse return null;

    // Check if TERMINFO is set
    if (std.posix.getenv("TERMINFO")) |path| {
        return tryPath(alloc, path, term);
    }

    // Check ~/.terminfo
    if (std.posix.getenv("HOME")) |home| {
        const path = try std.fmt.allocPrint(alloc, "{s}/.terminfo", .{home});
        defer alloc.free(path);

        if (tryPath(alloc, path, term)) |data| return data;
    }

    // Check TERMINFO_DIRS
    if (std.posix.getenv("TERMINFO_DIRS")) |dirs| {
        var iter = std.mem.tokenizeScalar(u8, dirs, ':');
        while (iter.next()) |dir| {
            const cdir = if (dir.len == 0) "/usr/share/terminfo" else dir;
            if (tryPath(alloc, cdir, term)) |data| return data;
        }
    }

    // fallback
    return tryPath(alloc, "/usr/share/terminfo", term);
}

pub fn copyString(alloc: Allocator, data: []const u8, str: i16, table: i16) ![]const u8 {
    // Get offset
    const off: i16 = @bitCast(data[@intCast(str)..][0..2].*);

    // Get pointer (null-terminated pointer)
    const src_ptr = @as([*c]const u8, &data[@as(usize, @intCast(table)) + @as(usize, @intCast(off))]);

    // Convert to slice (search for \0)
    const src = std.mem.span(src_ptr);

    // Duplicate
    return try alloc.dupe(u8, src);
}
