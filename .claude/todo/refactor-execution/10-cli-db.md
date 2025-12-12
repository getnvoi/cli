# 10 - CLI Database Execution

## Reference
Read from: `/Users/ben/Desktop/nvoi-rb/lib/nvoi/`

## Build

Create `lib/nvoi/cli/db/command.rb`:
- From `service/db.rb`
- Uses `External::Database::`, `External::SSH`, `Utils::`
- Methods: `branch_create`, `branch_list`, `branch_restore`, `branch_download`

Under `Nvoi::CLI::Db` namespace.

## Validate

- [ ] `ls lib/nvoi/cli/db/` shows command.rb
- [ ] All branch methods present

## Test

```bash
cd /Users/ben/Desktop/nvoi-rb-refactor
ruby -e "require './lib/nvoi/cli/db/command'; p Nvoi::CLI::Db::Command"
```

## Commit

```bash
git add -A && git commit -m "Phase 10: Build cli/db/"
```
