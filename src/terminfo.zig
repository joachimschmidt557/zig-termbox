const std = @import("std");
const Allocator = std.mem.Allocator;

fn tryPath(alloc: *Allocator, path: []const u8, term: []const u8) ?[]const u8 {
    const tmp = std.fmt.allocPrint(alloc, "{s}/{s}/{s}", .{ path, &[_]u8{term[0]}, term }) catch return null;
    defer alloc.free(tmp);

    return std.fs.cwd().readFileAlloc(alloc, tmp, std.math.maxInt(usize)) catch null;
}

pub fn loadTerminfo(alloc: *Allocator) !?[]const u8 {
    const term = std.os.getenv("TERM") orelse return null;

    // Check if TERMINFO is set
    if (std.os.getenv("TERMINFO")) |path| {
        return tryPath(alloc, path, term);
    }

    // Check ~/.terminfo
    if (std.os.getenv("HOME")) |home| {
        const path = try std.fmt.allocPrint(alloc, "{s}/.terminfo", .{home});
        defer alloc.free(path);

        if (tryPath(alloc, path, term)) |data| return data;
    }

    // Check TERMINFO_DIRS
    if (std.os.getenv("TERMINFO_DIRS")) |dirs| {
        var iter = std.mem.tokenize(dirs, ":");
        while (iter.next()) |dir| {
            const cdir = if (dir.len == 0) "/usr/share/terminfo" else dir;
            if (tryPath(alloc, cdir, term)) |data| return data;
        }
    }

    // fallback
    return tryPath(alloc, "/usr/share/terminfo", term);
}

pub fn copyString(alloc: *Allocator, data: []const u8, str: i16, table: i16) ![]const u8 {
    // Get offset
    const off = std.mem.readIntSliceNative(i16, data[@intCast(usize, str)..@intCast(usize, str + 2)]);

    // Get pointer (null-terminated pointer)
    const src_ptr = @as([*c]const u8, &data[@intCast(usize, table) + @intCast(usize, off)]);

    // Convert to slice (search for \0)
    const src = std.mem.spanZ(src_ptr);

    // Duplicate
    return try alloc.dupe(u8, src);
}
