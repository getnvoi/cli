# 08 - CLI Exec Execution

## Reference
Read from: `/Users/ben/Desktop/nvoi-rb/lib/nvoi/`

## Build

Create `lib/nvoi/cli/exec/command.rb`:
- From `service/exec.rb`
- Uses `External::SSH`, `Utils::`

Under `Nvoi::CLI::Exec` namespace.

## Validate

- [ ] `ls lib/nvoi/cli/exec/` shows command.rb
- [ ] Supports: single server, `--all`, `-i` interactive

## Test

```bash
cd /Users/ben/Desktop/nvoi-rb-refactor
ruby -e "require './lib/nvoi/cli/exec/command'; p Nvoi::CLI::Exec::Command"
```

## Commit

```bash
git add -A && git commit -m "Phase 8: Build cli/exec/"
```
