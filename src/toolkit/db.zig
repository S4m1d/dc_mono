const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});
const ConnList = std.DoublyLinkedList(DbConnection);

pub const ConnectionPool = struct {
    max_open: u8,
    in_use_conn_list: ConnList,
    idle_conn_list: ConnList,
    allocator: std.mem.Allocator,
    lock: std.Thread.RwLock,

    pub fn init(allocator: std.mem.Allocator, max_open: u8) !ConnectionPool {
        return ConnectionPool{
            .allocator = allocator,
            .max_open = max_open,
            .in_use_conn_list = ConnList{},
            .idle_conn_list = ConnList{},
            .lock = .{},
        };
    }

    pub fn deinit(self: *ConnectionPool) void {
        while (self.in_use_conn_list.pop()) |db_conn_node| {
            db_conn_node.data.deinit();
        }
    }

    pub fn acquire(self: *ConnectionPool) !Connection {
        self.lock.lock();
        defer self.lock.unlock();

        if (self.idle_conn_list.pop()) |node_to_acquire| {
            std.debug.print("DEBUG: found idle conn, returning it...\n", .{});
            self.in_use_conn_list.append(node_to_acquire);
            return Connection{ ._db_conn_node = node_to_acquire };
        }

        std.debug.print("DEBUG: no idle conns found, creating new...\n", .{});

        const db_conn = try DbConnection.init(self.allocator);

        var db_conn_node = try self.allocator.create(ConnList.Node);
        db_conn_node.data = db_conn;

        self.in_use_conn_list.append(db_conn_node);

        return .{ ._db_conn_node = db_conn_node };
    }

    pub fn release(self: *ConnectionPool, conn: Connection) void {
        self.lock.lock();
        defer self.lock.unlock();

        self.in_use_conn_list.remove(conn._db_conn_node);
        self.idle_conn_list.append(conn._db_conn_node);
    }
};

// wrapper I need to operate on connection abstracting user from linked list
pub const Connection = struct {
    _db_conn_node: *ConnList.Node,

    pub fn get(self: Connection) *DbConnection {
        return &self._db_conn_node.data;
    }
};

const PrpStmtsMap = std.hash_map.StringHashMap(?*c.sqlite3_stmt);

pub const DbConnection = struct {
    _allocator: std.mem.Allocator,
    _sqlite_conn: ?*c.sqlite3,
    _prp_stmts_map: PrpStmtsMap,

    pub fn init(allocator: std.mem.Allocator) !DbConnection {
        const prp_stmts_map = PrpStmtsMap.init(allocator);

        var sqlite_conn: ?*c.sqlite3 = null;

        const rc = c.sqlite3_open_v2("db/mydb.db", &sqlite_conn, c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_NOMUTEX, null);
        if (rc != c.SQLITE_OK) {
            std.debug.print("ERROR: couldn't acquire connection from pool: couldn't open connection: return code {d}\n", .{rc});
            return error.ErrOpenDbConn;
        }

        return .{
            ._allocator = allocator,
            ._sqlite_conn = sqlite_conn,
            ._prp_stmts_map = prp_stmts_map,
        };
    }

    pub fn deinit(self: *DbConnection) void {
        var it = self._prp_stmts_map.iterator();
        while (it.next()) |entry| {
            const rc = c.sqlite3_finalize(entry.value_ptr.*);
            if (rc != c.SQLITE_OK) {
                std.debug.print("WARNING: couldn't finalize statement: return code {d}\n", .{rc});
            }
        }

        self._prp_stmts_map.deinit();

        const rc = c.sqlite3_close_v2(self._sqlite_conn);
        if (rc != c.SQLITE_OK) {
            std.debug.print("WARNING: couldn't close connection: return code {d}\n", .{rc});
        }
    }

    pub fn statement(self: *DbConnection, query: []const u8) !?*c.sqlite3_stmt {
        if (self._prp_stmts_map.get(query)) |stmt| {
            std.debug.print("DEBUG: found statement for: [{s}], returning it...\n", .{query});
            return stmt;
        }

        var stmt: ?*c.sqlite3_stmt = null;
        std.debug.print("DEBUG: couldn't find statement for: [{s}], preparing new one...\n", .{query});
        const rc = c.sqlite3_prepare_v2(self._sqlite_conn, @ptrCast(query), -1, &stmt, null);
        if (rc != 0) {
            std.debug.print("couldn't prepare statement: return code {d}\n", .{rc});
            return error.ErrPrepStmt;
        }

        try self._prp_stmts_map.put(query, stmt);

        return stmt;
    }

    pub fn rst_statement(_: *DbConnection, stmt: ?*c.sqlite3_stmt) void {
        _ = c.sqlite3_reset(stmt);
    }
};
