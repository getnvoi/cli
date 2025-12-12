# 04 - External DNS Execution

## Reference
Read from: `/Users/ben/Desktop/nvoi-rb/lib/nvoi/`

## Build

Create `lib/nvoi/external/dns/` with:

| File | Content (from reference) |
|------|--------------------------|
| `cloudflare.rb` | Merge `cloudflare/client.rb` + `deployer/tunnel_manager.rb` (no Structs) |

Under `Nvoi::External::DNS` namespace.
Use `Objects::Tunnel`, `Objects::Zone`, `Objects::DNSRecord`, `Objects::TunnelInfo`.
Add `setup_tunnel` method from TunnelManager.

## Validate

- [ ] `ls lib/nvoi/external/dns/` shows 1 file
- [ ] No Struct definitions in file
- [ ] `setup_tunnel` method exists

## Test

```bash
cd /Users/ben/Desktop/nvoi-rb-refactor
ruby -e "require './lib/nvoi/objects/tunnel'; require './lib/nvoi/objects/dns'; require './lib/nvoi/external/dns/cloudflare'; p Nvoi::External::DNS::Cloudflare"
```

## Commit

```bash
git add -A && git commit -m "Phase 4: Build external/dns/"
```
