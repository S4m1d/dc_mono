const std = @import("std");
const User = @import("../model/user.zig").User;
const db = @import("../toolkit/db.zig");

const c = @cImport({
    @cInclude("sqlite3.h");
});

const last_insert_rowid_query = "SELECT last_insert_rowid();";
const create_query =
    \\ INSERT INTO users (username, password_hash, public_key)
    \\ VALUES (?,?,?);
;

pub fn create(db_conn: db.DbConnection, user: User) !i64 {
    const conn = db_conn._sqlite_conn;

    var create_stmt: ?*c.sqlite3_stmt = null;
    var rc = c.sqlite3_prepare_v2(conn, create_query, -1, &create_stmt, null);
    if (rc != 0) {
        std.debug.print("couldn't prepare statement for user create query: return code {d}\n", .{rc});
        return error.ErrPrepStmt;
    }

    rc = c.sqlite3_bind_text(create_stmt, 1, user.username.ptr, @intCast(user.username.len), c.SQLITE_TRANSIENT);
    if (rc != 0) {
        std.debug.print("couldn't bind username val: return code {d}\n", .{rc});
        return error.ErrBindVal;
    }

    const mock_pass_hash = [_]u8{ 0x44, 0x33, 0x55 };
    rc = c.sqlite3_bind_blob(create_stmt, 2, mock_pass_hash[0..].ptr, mock_pass_hash[0..].len, c.SQLITE_TRANSIENT);
    if (rc != 0) {
        std.debug.print("couldn't bind password_hash val: return code {d}\n", .{rc});
        return error.ErrBindVal;
    }

    const mock_pub_key = [_]u8{ 0x33, 0x44, 0x55 };
    rc = c.sqlite3_bind_blob(create_stmt, 3, mock_pub_key[0..].ptr, mock_pub_key[0..].len, c.SQLITE_TRANSIENT);
    if (rc != 0) {
        std.debug.print("couldn't bind public_key val: return code {d}\n", .{rc});
        return error.ErrBindVal;
    }

    rc = c.sqlite3_step(create_stmt);
    if (rc != c.SQLITE_DONE) {
        const errmsg = c.sqlite3_errmsg(conn);
        std.debug.print("couldn't execute user create query: return code {d}, diag:{s}\n", .{ rc, errmsg });
        return error.ErrStep;
    }

    rc = c.sqlite3_finalize(create_stmt);
    if (rc != c.SQLITE_OK) {
        std.debug.print("couldn't finalize create user statement: return code {d}\n", .{rc});
        return error.ErrStmtFnlz;
    }

    var last_insert_rowid_stmt: ?*c.sqlite3_stmt = null;
    rc = c.sqlite3_prepare_v2(conn, last_insert_rowid_query, -1, &last_insert_rowid_stmt, null);
    if (rc != 0) {
        std.debug.print("couldn't prepare statement for last created user id fetching query: return code {d}\n", .{rc});
        return error.ErrPrepStmt;
    }

    rc = c.sqlite3_step(last_insert_rowid_stmt);
    if (rc != c.SQLITE_ROW) {
        const errmsg = c.sqlite3_errmsg(conn);
        std.debug.print("couldn't execute last created user id fetching query: return code {d}, diag: {s}\n", .{ rc, errmsg });
        return error.ErrStep;
    }

    const user_id = c.sqlite3_column_int64(last_insert_rowid_stmt, 0);

    rc = c.sqlite3_finalize(last_insert_rowid_stmt);
    if (rc != c.SQLITE_OK) {
        std.debug.print("couldn't finalize last created user id fetch statement: return code {d}\n", .{rc});
        return error.ErrStmtFnlz;
    }

    return user_id;
}
