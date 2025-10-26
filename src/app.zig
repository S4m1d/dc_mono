const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const App = struct {
    allocator: std.mem.Allocator,
    db: ?*c.sqlite3,
};
