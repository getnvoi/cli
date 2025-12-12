# 12 - CLI: Database Commands

## Priority: FIFTH (parallel with others)

---

## Current State (NEW from main)

| File | Lines | Purpose |
|------|-------|---------|
| `service/db.rb` | 285 | DbService - database branch operations |
| `database/provider.rb` | 160 | Base provider + factory + structs |
| `database/postgres.rb` | ~100 | Postgres dump/restore |
| `database/mysql.rb` | ~100 | MySQL dump/restore |
| `database/sqlite.rb` | ~80 | SQLite dump/restore |

**Total: ~725 lines**

---

## What It Does

Database "branching" = snapshots for backup/restore:

```bash
nvoi db branch create [name]      # Dump current DB to file
nvoi db branch list               # List saved branches
nvoi db branch restore <id>       # Restore branch to new DB
nvoi db branch download <id>      # Download dump locally
```

---

## Target Structure

```
lib/nvoi/cli/db/
├── command.rb                    # Router for subcommands
├── branch/
│   ├── create/
│   │   └── command.rb
│   ├── list/
│   │   └── command.rb
│   ├── restore/
│   │   └── command.rb
│   └── download/
│       └── command.rb
```

OR simpler (single file since operations are small):

```
lib/nvoi/cli/db/
└── command.rb                    # All branch operations
```

---

## Database Module → External

The `database/` providers are external adapters (talk to DBs via kubectl exec):

```
lib/nvoi/external/database/
├── provider.rb                   # Base + factory
├── postgres.rb
├── mysql.rb
└── sqlite.rb
```

**Note:** These use `kubectl exec` to run dump/restore commands in pods. They're external adapters like cloud providers.

---

## Objects to Extract

From `database/provider.rb`:

```ruby
# objects/database.rb
Credentials = Struct.new(:user, :password, :host, :port, :database, :path, keyword_init: true)
DumpOptions = Struct.new(:pod_name, :database, :user, :password, :host_path, keyword_init: true)
RestoreOptions = Struct.new(:pod_name, :database, :user, :password, :source_db, :host_path, keyword_init: true)
CreateOptions = Struct.new(:pod_name, :database, :user, :password, keyword_init: true)
Branch = Struct.new(:id, :created_at, :size, :adapter, :database, keyword_init: true)
BranchMetadata  # class with branches array
```

---

## DRY Opportunities

### 1. SSH Helper Pattern
`DbService#with_ssh` creates SSH executor. Same pattern in other services.
Extract to base or mixin:

```ruby
# In command base or utils
def with_master_ssh(config, provider)
  server_ip = get_master_server_ip(config, provider)
  ssh = External::SSH.new(server_ip, config.ssh_key_path)
  yield ssh
end
```

### 2. Database Credentials Resolution
`Config::DatabaseHelper.get_credentials` is called from multiple places.
Keep in config or move to database provider factory.

---

## Migration Steps

1. Create `lib/nvoi/external/database/` directory
2. Move `database/*.rb` → `external/database/`
3. Extract Structs to `objects/database.rb`
4. Create `lib/nvoi/cli/db/command.rb`
5. Move logic from `service/db.rb` → `cli/db/command.rb`
6. Delete `service/db.rb`

---

## Estimated Effort

- **Lines to reorganize:** ~725
- **Files created:** 5 (1 command + 4 external/database)
- **Files deleted/moved:** 5
- **Net change:** minimal (reorganization)
