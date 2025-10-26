pub const User = struct {
    id: ?i64,
    username: []u8,
    password_hash: []u8,
    public_key: []u8,
};
