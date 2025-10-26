# DB init
```sql
CREATE TABLE users(
id INTEGER PRIMARY KEY AUTOINCREMENT,
username VARCHAR(16) NOT NULL,
password_hash BLOB NOT NULL
, public_key BLOB NOT NULL);
```

