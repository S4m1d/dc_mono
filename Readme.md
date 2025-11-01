# Overview
This is monolith app (backend + web front) for *Dodging Cat* p2p messenger.
Messenger is designed for maximum security: 
- uses end2end encryption for all messages, what prevents private data leak in case of server and it's db compromise.
- private key for messege decryption never leaves users machine.

# DB init
```sql
CREATE TABLE users(
id INTEGER PRIMARY KEY AUTOINCREMENT,
username VARCHAR(16) NOT NULL,
password_hash BLOB NOT NULL
, public_key BLOB NOT NULL);
```

