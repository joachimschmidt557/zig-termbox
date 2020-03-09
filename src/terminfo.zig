const std = @import("std");
const Allocator = std.mem.Allocator;
const Buffer = std.Buffer;

fn tryPath(alloc: *Allocator, path: []const u8, term: []const u8) ?[]const u8 {
    const tmp = Buffer.initSize(alloc, 0);
    defer tmp.deinit();

    tmp.print("{}/{}/{}", .{ path, term[0], term });

    const file = std.fs.openFileAbsolute(tmp, .{}) catch return null;
    return file.inStream().stream.readAllAlloc(alloc, 1024) catch null;
}

fn loadTerminfo(alloc: *Allocator) ?[]const u8 {
    const term = std.os.getenv("TERM") orelse return null;

    if (std.os.getenv("TERMINFO")) |path| {
        return tryPath(alloc, path, term);
    }
}
