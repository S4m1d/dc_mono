const std = @import("std");
const httpz = @import("httpz");
const App = @import("../app.zig").App;
const userRepo = @import("../repository/users.zig");

const UserRegReqBody = struct {
    username: []u8,
    password_hash: []u8,
    public_key: []u8,
};

pub fn postRegisterUser(app: *App, req: *httpz.Request, res: *httpz.Response) !void {
    if (try req.json(UserRegReqBody)) |body| {
        const id = try userRepo.create(app.db, .{
            .id = null,
            .username = body.username,
            .public_key = body.public_key,
            .password_hash = body.password_hash,
        });

        try res.json(.{
            .id = id,
        }, .{});
    }
}
