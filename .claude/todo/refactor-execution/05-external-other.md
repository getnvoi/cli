# 05 - External Other Execution

## Reference
Read from: `/Users/ben/Desktop/nvoi-rb/lib/nvoi/`

## Build

Create in `lib/nvoi/external/`:

| File | Content (from reference) |
|------|--------------------------|
| `ssh.rb` | From `remote/ssh_executor.rb` |
| `kubectl.rb` | Extract kubectl ops from `k8s/renderer.rb` |
| `containerd.rb` | From `remote/docker_manager.rb` (rename class) |
| `volume_manager.rb` | From `remote/volume_manager.rb` (no MountOptions Struct) |

Create `lib/nvoi/external/database/`:

| File | Content (from reference) |
|------|--------------------------|
| `provider.rb` | From `database/provider.rb` (no Structs, use `Objects::`) |
| `postgres.rb` | From `database/postgres.rb` |
| `mysql.rb` | From `database/mysql.rb` |
| `sqlite.rb` | From `database/sqlite.rb` |

Under `Nvoi::External` namespace.
Use `Objects::MountOptions`, `Objects::DatabaseCredentials`, etc.

## Validate

- [ ] `ls lib/nvoi/external/` shows ssh.rb, kubectl.rb, containerd.rb, volume_manager.rb
- [ ] `ls lib/nvoi/external/database/` shows 4 files
- [ ] No Struct definitions in any file

## Test

```bash
cd /Users/ben/Desktop/nvoi-rb-refactor
ruby -e "require './lib/nvoi/external/ssh'; p Nvoi::External::SSH"
```

## Commit

```bash
git add -A && git commit -m "Phase 5: Build external/ssh, kubectl, containerd, database"
```
