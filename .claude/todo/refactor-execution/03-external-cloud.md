# 03 - External Cloud Execution

## Reference
Read from: `/Users/ben/Desktop/nvoi-rb/lib/nvoi/`

## Build

Create `lib/nvoi/external/cloud/` with:

| File | Content (from reference) |
|------|--------------------------|
| `base.rb` | From `providers/base.rb` (interface only, no Structs) |
| `hetzner.rb` | Merge `providers/hetzner.rb` + `providers/hetzner_client.rb` |
| `aws.rb` | From `providers/aws.rb` |
| `scaleway.rb` | Merge `providers/scaleway.rb` + `providers/scaleway_client.rb` |
| `factory.rb` | From `service/provider.rb` (ProviderHelper → `External::Cloud.for(config)`) |

All under `Nvoi::External::Cloud` namespace.
Use `Objects::Server`, `Objects::Network`, etc.

## Validate

- [ ] `ls lib/nvoi/external/cloud/` shows 5 files
- [ ] `base.rb` has no Struct definitions
- [ ] Each provider uses `Objects::` for return types

## Test

```bash
cd /Users/ben/Desktop/nvoi-rb-refactor
ruby -e "require './lib/nvoi/objects/server'; require './lib/nvoi/external/cloud/base'; p Nvoi::External::Cloud::Base"
```

## Commit

```bash
git add -A && git commit -m "Phase 3: Build external/cloud/"
```
