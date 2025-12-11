# 04 - External: DNS Provider (Cloudflare)

## Priority: THIRD (parallel with cloud)

---

## Current State

| File                         | Lines | Purpose                    |
| ---------------------------- | ----- | -------------------------- |
| `cloudflare/client.rb`       | 288   | Cloudflare API client      |
| `deployer/tunnel_manager.rb` | 58    | Tunnel setup orchestration |

**Total: ~346 lines across 2 files**

---

## Target Structure

```
lib/nvoi/external/dns/
└── cloudflare.rb       # Full Cloudflare client (tunnels + DNS)
```

---

## What Cloudflare Client Does

### Tunnel Operations

- `create_tunnel(name)` → Tunnel
- `find_tunnel(name)` → Tunnel | nil
- `get_tunnel_token(tunnel_id)` → String
- `update_tunnel_configuration(tunnel_id, hostname, service_url)`
- `verify_tunnel_configuration(tunnel_id, hostname, service_url, attempts)`
- `delete_tunnel(tunnel_id)`

### DNS Operations

- `find_zone(domain)` → Zone | nil
- `find_dns_record(zone_id, name, type)` → DNSRecord | nil
- `create_dns_record(zone_id, name, type, content, proxied:)`
- `update_dns_record(zone_id, record_id, name, type, content, proxied:)`
- `create_or_update_dns_record(...)` → convenience method
- `delete_dns_record(zone_id, record_id)`

---

## DRY Opportunities

### 1. Absorb TunnelManager into Cloudflare Client

`TunnelManager.setup_tunnel` does:

1. Find or create tunnel
2. Get token
3. Configure ingress
4. Verify configuration
5. Create DNS record

This is just a convenience method. Move into client:

```ruby
# external/dns/cloudflare.rb
class Cloudflare
  # Existing low-level methods...

  # High-level convenience
  def setup_tunnel(name, hostname, service_url, domain)
    tunnel = find_tunnel(name) || create_tunnel(name)
    token = tunnel.token || get_tunnel_token(tunnel.id)
    update_tunnel_configuration(tunnel.id, hostname, service_url)
    verify_tunnel_configuration(tunnel.id, hostname, service_url, Constants::TUNNEL_CONFIG_VERIFY_ATTEMPTS)

    zone = find_zone(domain)
    create_or_update_dns_record(zone.id, hostname, "CNAME", "#{tunnel.id}.cfargotunnel.com")

    Objects::TunnelInfo.new(tunnel_id: tunnel.id, tunnel_token: token)
  end
end
```

### 2. Remove Struct Definitions

Move `Tunnel`, `Zone`, `DNSRecord` to `objects/` (done in 01-objects.md)

---

## Migration Steps

1. Create `lib/nvoi/external/dns/` directory
2. Move `cloudflare/client.rb` → `external/dns/cloudflare.rb`
3. Merge `deployer/tunnel_manager.rb` into Cloudflare as `setup_tunnel` method
4. Remove Struct definitions (use from `objects/`)
5. Update namespace from `Cloudflare::Client` to `External::DNS::Cloudflare`

---

## Estimated Effort

- **Lines to consolidate:** ~346
- **Files created:** 1
- **Files deleted:** 2
- **DRY savings:** ~20 lines (TunnelManager overhead)
