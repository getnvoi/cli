# 02 - Utils Execution

## Reference
Read from: `/Users/ben/Desktop/nvoi-rb/lib/nvoi/`

## Build

Create `lib/nvoi/utils/` with:

| File | Content (from reference) |
|------|--------------------------|
| `logger.rb` | From `logger.rb` |
| `constants.rb` | From `constants.rb` |
| `errors.rb` | From `errors.rb` |
| `namer.rb` | From `config/naming.rb` + add `hostname(subdomain, domain)` |
| `env_resolver.rb` | From `config/env_resolver.rb` |
| `config_loader.rb` | Merge `config/loader.rb` + `config/ssh_keys.rb` |
| `crypto.rb` | Merge `credentials/crypto.rb` + `credentials/manager.rb` |
| `templates.rb` | Merge `k8s/templates.rb` + `k8s/renderer.rb` |
| `retry.rb` | From `deployer/retry.rb` |

All under `Nvoi::Utils` namespace.

## Validate

- [ ] `ls lib/nvoi/utils/` shows 9 files
- [ ] Each file has `module Nvoi::Utils`
- [ ] `hostname` method added to namer

## Test

```bash
cd /Users/ben/Desktop/nvoi-rb-refactor
ruby -e "require './lib/nvoi/utils/logger'; Nvoi::Utils::Logger.new.info('test')"
```

## Commit

```bash
git add -A && git commit -m "Phase 2: Build utils/"
```
