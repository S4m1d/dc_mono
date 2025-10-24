const std = @import("std");

pub const Static = struct {
    pub fn init() !Static {
        // TODO: init cache and add deinit function
        return Static{};
    }

    pub fn readFresh(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
        // TODO: use cache
        const full_path = try std.mem.concat(allocator, u8, &.{ "assets/", name });
        defer allocator.free(full_path);

        const file = try std.fs.cwd().openFile(full_path, .{});
        defer file.close();

        const size_bytes = (try file.stat()).size;

        const buf: []u8 = try allocator.alloc(u8, size_bytes);

        _ = try file.readAll(buf);

        return buf;
    }
};
