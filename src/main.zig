const std = @import("std");
const StaticRes = @import("server/resource.zig").Static;
const httpz = @import("httpz");
const App = @import("app.zig").App;
const registration = @import("server/registration.zig");
const db = @import("toolkit/db.zig");

const c = @cImport({
    @cInclude("sqlite3.h");
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var conn_pool = try db.ConnectionPool.init(allocator, 10);
    defer conn_pool.deinit();

    var app = App{
        .allocator = allocator,
        .conn_pool = &conn_pool,
    };

    var server = try httpz.Server(*App).init(allocator, .{ .port = 8080 }, &app);
    var router = try server.router(.{});
    router.post("/user/register", registration.postRegisterUser, .{});
    router.get("/info", getInfo, .{});
    router.get("/index.html", getIndexHtml, .{});
    try server.listen();
}

fn getInfo(_: *App, _: *httpz.Request, res: *httpz.Response) !void {
    try res.json(.{
        .hello = "friend",
        .leave_me = "here",
    }, .{});
}

fn getIndexHtml(app: *App, _: *httpz.Request, res: *httpz.Response) !void {
    const index_html_content = try StaticRes.readFresh(app.allocator, "pages/index.html");
    defer app.allocator.free(index_html_content);
    res.body = index_html_content;
    try res.write();
}
