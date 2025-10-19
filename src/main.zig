const std = @import("std");

var is_app_active = std.atomic.Value(bool).init(true);

pub fn main() !void {
    const address = try std.net.Address.parseIp4("127.0.0.1", 8080);

    var server = try address.listen(.{});
    defer server.deinit();
    defer std.debug.print("gracefull shutdown works!", .{});

    var sa = std.posix.Sigaction{
        .handler = .{ .handler = handleOsSig },
        .mask = std.posix.empty_sigset,
        .flags = 0,
        .restorer = null,
    };

    std.posix.sigaction(std.posix.SIG.INT, &sa, null);

    while (is_app_active.load(.seq_cst)) {
        try handleConn(try server.accept());
    }
}

pub fn handleConn(conn: std.net.Server.Connection) !void {
    defer conn.stream.close();
    var buffer: [1024]u8 = undefined;
    var http_server = std.http.Server.init(conn, &buffer);
    var req = try http_server.receiveHead();
    try req.respond("fuck off\n", .{});
}

pub fn handleOsSig(signo: i32) callconv(.c) void {
    if (signo == std.posix.SIG.INT or signo == std.posix.SIG.TERM) {
        // chose the most relaxed and fast type of ordering for now
        is_app_active.store(false, .seq_cst);
    }
}
