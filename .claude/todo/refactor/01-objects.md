# 01 - Objects (Domain Entities)

## Priority: FIRST

Objects have no dependencies. Everything else depends on them.

---

## Current State

Scattered across multiple files:

| Object                                                        | Current Location       | Lines |
| ------------------------------------------------------------- | ---------------------- | ----- |
| `Server`, `Network`, `Firewall`, `Volume`                     | `providers/base.rb`    | ~20   |
| `ServerCreateOptions`, `VolumeCreateOptions`                  | `providers/base.rb`    | ~5    |
| `Tunnel`, `Zone`, `DNSRecord`                                 | `cloudflare/client.rb` | ~10   |
| `TunnelInfo`                                                  | `deployer/types.rb`    | ~3    |
| `ServiceSpec`                                                 | `config/types.rb`      | ~20   |
| `MountOptions`, `ContainerRunOptions`, `WaitForHealthOptions` | `remote/*.rb`          | ~10   |
| Config types (15+ classes)                                    | `config/types.rb`      | ~290  |

**Total: ~360 lines scattered across 5 files**

---

## Target Structure

```
lib/nvoi/objects/
├── server.rb           # Server, ServerCreateOptions
├── network.rb          # Network
├── firewall.rb         # Firewall
├── volume.rb           # Volume, VolumeCreateOptions, MountOptions
├── tunnel.rb           # Tunnel, TunnelInfo
├── dns.rb              # Zone, DNSRecord
├── service_spec.rb     # ServiceSpec (K8s deployment spec)
└── config.rb           # All config types consolidated
```

---

## DRY Opportunities

### 1. Config Types Consolidation

Current `config/types.rb` has 15+ classes. Keep them but in `objects/config.rb`.

### 2. Struct vs Class

Many objects are simple Structs. Keep them as Structs:

```ruby
# objects/server.rb
module Nvoi
  module Objects
    Server = Struct.new(:id, :name, :status, :public_ipv4, keyword_init: true)
    ServerCreateOptions = Struct.new(:name, :type, :image, :location, :user_data, :network_id, :firewall_id, keyword_init: true)
  end
end
```

### 3. TunnelInfo Duplication

`TunnelInfo` in `deployer/types.rb` is basically `Tunnel` + extra fields. Merge:

```ruby
# objects/tunnel.rb
module Nvoi
  module Objects
    Tunnel = Struct.new(:id, :name, :token, keyword_init: true)
    TunnelInfo = Struct.new(:service_name, :hostname, :tunnel_id, :tunnel_token, :port, keyword_init: true)
  end
end
```

---

## Migration Steps

1. Create `lib/nvoi/objects/` directory
2. Extract Structs from `providers/base.rb` → `objects/server.rb`, `objects/network.rb`, etc.
3. Extract Structs from `cloudflare/client.rb` → `objects/tunnel.rb`, `objects/dns.rb`
4. Move `deployer/types.rb` → `objects/tunnel.rb` (merge TunnelInfo)
5. Move `config/types.rb` → `objects/config.rb`
6. Extract `MountOptions` from `remote/volume_manager.rb` → `objects/volume.rb`
7. Update all requires in `lib/nvoi.rb`

---

## Estimated Effort

- **Lines to move:** ~360
- **Files created:** 8
- **Files deleted:** 1 (`deployer/types.rb`)
- **Files modified:** 4 (remove struct definitions)
