# 07 - CLI Delete Execution

## Reference
Read from: `/Users/ben/Desktop/nvoi-rb/lib/nvoi/`

## Build

Create `lib/nvoi/cli/delete/command.rb`:
- Orchestrator from `service/delete.rb`
- Uses `External::`, `Utils::`, `Objects::`

Create `lib/nvoi/cli/delete/steps/`:

| File | Content (from reference) |
|------|--------------------------|
| `detach_volumes.rb` | Extract from `service/delete.rb` |
| `teardown_server.rb` | Extract from `service/delete.rb` |
| `teardown_volume.rb` | Extract from `service/delete.rb` |
| `teardown_firewall.rb` | Extract from `service/delete.rb` |
| `teardown_network.rb` | Extract from `service/delete.rb` |
| `teardown_tunnel.rb` | Extract from `service/delete.rb` |
| `teardown_dns.rb` | Extract from `service/delete.rb` |

Under `Nvoi::CLI::Delete` namespace.

## Validate

- [ ] `ls lib/nvoi/cli/delete/` shows command.rb + steps/
- [ ] `ls lib/nvoi/cli/delete/steps/` shows 7 files
- [ ] Teardown order correct: detach → servers → volumes → firewall → network → tunnel → dns

## Test

```bash
cd /Users/ben/Desktop/nvoi-rb-refactor
ruby -e "require './lib/nvoi/cli/delete/command'; p Nvoi::CLI::Delete::Command"
```

## Commit

```bash
git add -A && git commit -m "Phase 7: Build cli/delete/"
```
