const std = @import("std");
const db = @import("toolkit/db.zig");
const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const App = struct {
    allocator: std.mem.Allocator,
    conn_pool: *db.ConnectionPool,
};
