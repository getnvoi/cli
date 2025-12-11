# 03 - External: Cloud Providers

## Priority: THIRD

External adapters depend on Objects and Utils.

---

## Current State

| File                           | Lines | Purpose                      |
| ------------------------------ | ----- | ---------------------------- |
| `providers/base.rb`            | 112   | Abstract interface + Structs |
| `providers/hetzner.rb`         | 289   | Hetzner Cloud implementation |
| `providers/hetzner_client.rb`  | ~200  | Hetzner HTTP client          |
| `providers/aws.rb`             | ~250  | AWS implementation           |
| `providers/scaleway.rb`        | ~280  | Scaleway implementation      |
| `providers/scaleway_client.rb` | ~200  | Scaleway HTTP client         |
| `service/provider.rb`          | ~50   | Provider factory helper      |

**Total: ~1380 lines across 7 files**

---

## Target Structure

```
lib/nvoi/external/cloud/
├── base.rb             # Abstract interface (methods only, no Structs)
├── hetzner.rb          # Hetzner (merge provider + client)
├── aws.rb              # AWS
├── scaleway.rb         # Scaleway (merge provider + client)
└── factory.rb          # Provider initialization helper
```

---

## What Each Provider Does

All providers implement:

```ruby
# Network operations
find_or_create_network(name)
get_network_by_name(name)
delete_network(id)

# Firewall operations
find_or_create_firewall(name)
get_firewall_by_name(name)
delete_firewall(id)

# Server operations
find_server(name)
list_servers
create_server(opts)
wait_for_server(server_id, max_attempts)
delete_server(id)

# Volume operations
create_volume(opts)
get_volume(id)
get_volume_by_name(name)
delete_volume(id)
attach_volume(volume_id, server_id)
detach_volume(volume_id)

# Validation
validate_instance_type(instance_type)
validate_region(region)
validate_credentials
```

---

## DRY Opportunities

### 1. Merge Provider + Client

Current pattern:

- `hetzner.rb` = high-level operations
- `hetzner_client.rb` = HTTP calls

Merge into single file. The "client" is just private methods:

```ruby
# external/cloud/hetzner.rb
module Nvoi
  module External
    module Cloud
      class Hetzner < Base
        def find_server(name) ... end  # public

        private

        def get(path) ... end          # HTTP helpers
        def post(path, body) ... end
      end
    end
  end
end
```

### 2. Extract Common HTTP Client

All providers do similar HTTP work. Extract base:

```ruby
# external/cloud/base.rb
class Base
  private

  def http_get(url, headers = {}) ... end
  def http_post(url, body, headers = {}) ... end
  def handle_response(response) ... end
end
```

### 3. Provider Factory

Current `service/provider.rb` has `ProviderHelper` module. Move to:

```ruby
# external/cloud/factory.rb
module Nvoi
  module External
    module Cloud
      def self.for(config)
        case config.provider_name
        when "hetzner" then Hetzner.new(config.hetzner.api_token)
        when "aws" then AWS.new(config.aws)
        when "scaleway" then Scaleway.new(config.scaleway)
        end
      end
    end
  end
end
```

### 4. Struct Extraction (already in 01-objects.md)

Remove `Server`, `Network`, etc. from `base.rb` → use from `objects/`

---

## Migration Steps

1. Create `lib/nvoi/external/cloud/` directory
2. Create `base.rb` with interface only (no Structs)
3. Merge `hetzner.rb` + `hetzner_client.rb` → `external/cloud/hetzner.rb`
4. Move `aws.rb` → `external/cloud/aws.rb`
5. Merge `scaleway.rb` + `scaleway_client.rb` → `external/cloud/scaleway.rb`
6. Move `service/provider.rb` → `external/cloud/factory.rb`
7. Update requires to use `Objects::Server`, etc.

---

## Estimated Effort

- **Lines to consolidate:** ~1380
- **Files created:** 5
- **Files deleted:** 7
- **DRY savings:** ~100 lines (merged clients, shared HTTP base)
