const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});
const ConnList = std.DoublyLinkedList(DbConnection);

pub const ConnectionPool = struct {
    _max_open: u8,
    _in_use_conn_list: ConnList,
    _idle_conn_list: ConnList,
    _allocator: std.mem.Allocator,
    _in_use_mu: std.Thread.Mutex,
    _mu: std.Thread.Mutex,
    _cond: std.Thread.Condition,
    _num_open: usize,
    _num_qued_to_open: usize,
    _num_idle: usize,

    pub fn init(allocator: std.mem.Allocator, max_open: u8) !ConnectionPool {
        return ConnectionPool{
            ._allocator = allocator,
            ._max_open = max_open,
            ._in_use_conn_list = ConnList{},
            ._idle_conn_list = ConnList{},
            ._in_use_mu = .{},
            ._mu = .{},
            ._cond = .{},
            ._num_open = 0,
            ._num_qued_to_open = 0,
            ._num_idle = 0,
        };
    }

    pub fn deinit(self: *ConnectionPool) void {
        while (self._in_use_conn_list.pop()) |db_conn_node| {
            db_conn_node.data.deinit();
        }
    }

    pub fn acquire(self: *ConnectionPool) !Connection {
        while (true) {
            self._mu.lock();
            defer self._mu.unlock();

            // if there is available idle conn, return it
            if (self._num_idle > 0) {
                std.debug.print("DEBUG: found idle conn, returning it...\n", .{});
                const node_to_acquire = self._idle_conn_list.pop().?;
                self._num_idle -= 1;

                self._in_use_mu.lock();
                self._in_use_conn_list.append(node_to_acquire);
                self._in_use_mu.unlock();

                return Connection{ ._db_conn_node = node_to_acquire };
            }
            // else if open connections limit is not reached yet, open new connection and put it into idle list
            else if (self._num_open + self._num_qued_to_open < self._max_open) {
                std.debug.print("DEBUG: new connection can be open, launching detached thread...\n", .{});
                const th = try std.Thread.spawn(.{}, openConn, .{self});
                th.detach();
                self._num_qued_to_open += 1;
            }

            // else wait for next available idle connection
            self._cond.wait(&self._mu);
        }
    }

    pub fn openConn(self: *ConnectionPool) void {
        {
            self._mu.lock();
            defer self._mu.unlock();
            const db_conn = DbConnection.init(self._allocator) catch |err| {
                std.debug.print("failed to open db connection: caught error from connection init: {}", .{err});
                return;
            };
            errdefer db_conn.deinit();

            var db_conn_node = self._allocator.create(ConnList.Node) catch |err| {
                std.debug.print("failed to open db connection: caught error from node allocation: {}", .{err});
                return;
            };

            db_conn_node.data = db_conn;
            self._num_open += 1;

            self._idle_conn_list.append(db_conn_node);
            self._num_idle += 1;
        }

        // signaling here AFTER unlocking mutex
        // because otherwise we can run into unlocking mutex, that is relocked by wait
        // which leads to undefined behaviour
        self._cond.signal();
    }

    pub fn release(self: *ConnectionPool, conn: Connection) void {
        {
            self._mu.lock();
            defer self._mu.unlock();

            self._in_use_mu.lock();
            self._in_use_conn_list.remove(conn._db_conn_node);
            self._in_use_mu.unlock();

            self._idle_conn_list.append(conn._db_conn_node);
            self._num_idle += 1;
        }

        // signaling here AFTER unlocking mutex
        // because otherwise we can run into unlocking mutex, that is relocked by wait
        // which leads to undefined behaviour
        self._cond.signal();
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
