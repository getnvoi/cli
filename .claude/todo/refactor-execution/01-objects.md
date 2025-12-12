# 01 - Objects Execution

## Reference
Read from: `/Users/ben/Desktop/nvoi-rb/lib/nvoi/`

## Build

Create `lib/nvoi/objects/` with:

| File | Content (from reference) |
|------|--------------------------|
| `server.rb` | `Server`, `ServerCreateOptions` from `providers/base.rb` |
| `network.rb` | `Network` from `providers/base.rb` |
| `firewall.rb` | `Firewall` from `providers/base.rb` |
| `volume.rb` | `Volume`, `VolumeCreateOptions` from `providers/base.rb`, `MountOptions` from `remote/volume_manager.rb` |
| `tunnel.rb` | `Tunnel` from `cloudflare/client.rb`, `TunnelInfo` from `deployer/types.rb` |
| `dns.rb` | `Zone`, `DNSRecord` from `cloudflare/client.rb` |
| `database.rb` | `DatabaseCredentials`, `DumpOptions`, `RestoreOptions`, `CreateOptions`, `Branch`, `BranchMetadata` from `database/provider.rb` |
| `service_spec.rb` | `ServiceSpec` from `config/types.rb` |

All under `Nvoi::Objects` namespace.

## Validate

- [ ] `ls lib/nvoi/objects/` shows 8 files
- [ ] Each file has `module Nvoi::Objects`
- [ ] Structs match reference

## Test

```bash
cd /Users/ben/Desktop/nvoi-rb-refactor
ruby -e "require './lib/nvoi/objects/server'; p Nvoi::Objects::Server.new(id: '1', name: 'test', status: 'running', public_ipv4: '1.2.3.4')"
```

(Full test suite runs after all phases complete)

## Commit

```bash
git add -A && git commit -m "Phase 1: Build objects/"
```
