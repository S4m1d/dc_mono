const std = @import("std");
const StaticRes = @import("server/resource.zig").Static;
const httpz = @import("httpz");
const sqlite = @import("sqlite");

const App = struct {
    allocator: std.mem.Allocator,
    db: sqlite.Db,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "db/mydb.db" },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });

    var app = App{
        .allocator = allocator,
        .db = db,
    };

    var server = try httpz.Server(*App).init(allocator, .{ .port = 8080 }, &app);
    var router = try server.router(.{});
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
