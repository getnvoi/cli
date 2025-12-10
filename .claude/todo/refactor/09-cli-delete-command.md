# 09 - CLI: Delete Command

## Priority: FIFTH (parallel with deploy)

---

## Current State

| File                | Lines | Purpose                                |
| ------------------- | ----- | -------------------------------------- |
| `service/delete.rb` | 235   | DeleteService - teardown all resources |

---

## Target Structure

```
lib/nvoi/cli/delete/
├── command.rb
└── steps/
    ├── teardown_tunnel.rb
    ├── teardown_dns.rb
    ├── detach_volumes.rb
    ├── teardown_server.rb
    ├── teardown_volume.rb
    ├── teardown_firewall.rb
    └── teardown_network.rb
```

---

## What Delete Does (Current)

```ruby
def run
  detach_volumes          # Must happen before server deletion
  delete_all_servers      # Delete servers from all groups
  delete_volumes          # Now safe to delete
  delete_firewall         # With retry (might still be attached)
  delete_network
  delete_cloudflare_resources  # Tunnels + DNS records
end
```

---

## Target Flow

```ruby
# cli/delete/command.rb
class Command
  def run
    config = Utils::ConfigLoader.new.load(config_path)
    provider = External::Cloud.for(config)
    cloudflare = External::DNS::Cloudflare.new(config.cloudflare)
    log = Utils::Logger.new

    # Order matters!
    Steps::DetachVolumes.new(config, provider, log).run
    Steps::TeardownServer.new(config, provider, log).run
    Steps::TeardownVolume.new(config, provider, log).run
    Steps::TeardownFirewall.new(config, provider, log).run
    Steps::TeardownNetwork.new(config, provider, log).run
    Steps::TeardownTunnel.new(config, cloudflare, log).run
    Steps::TeardownDNS.new(config, cloudflare, log).run

    log.success "Cleanup complete"
  end
end
```

---

## DRY Opportunities

### 1. Shared Volume Name Collection

Both `detach_volumes` and `delete_volumes` call `collect_volume_names`.
Extract to utils or pass as step output:

```ruby
volumes = Steps::DetachVolumes.new(...).run  # returns volume list
Steps::TeardownVolume.new(...).run(volumes)
```

### 2. Shared Hostname Builder

`build_hostname` is duplicated. Already planned for `utils/namer.rb`.

### 3. Merge Tunnel + DNS Teardown

Both iterate over app services with domains. Could be single step:

```ruby
Steps::TeardownCloudflare.new(config, cloudflare, log).run
# Deletes both tunnels and DNS records
```

### 4. Error Tolerance

Delete operations should be idempotent. Current code does:

```ruby
rescue StandardError => e
  @log.warning "Failed to delete: %s", e.message
end
```

Keep this pattern - deletion should continue even if some resources are already gone.

---

## Step Details

### detach_volumes.rb (~40 lines)

- Collect all volume names
- For each: find volume, detach if attached

### teardown_server.rb (~50 lines)

- For each server group:
  - For each server in group:
    - Find and delete server

### teardown_volume.rb (~40 lines)

- For each volume name:
  - Find and delete volume

### teardown_firewall.rb (~30 lines)

- Find firewall by name
- Delete with retry (may still be detaching)

### teardown_network.rb (~20 lines)

- Find network by name
- Delete

### teardown_tunnel.rb (~40 lines)

- For each app service with domain:
  - Find and delete tunnel

### teardown_dns.rb (~40 lines)

- For each app service with domain:
  - Find zone
  - Find and delete CNAME record

---

## Migration Steps

1. Create `lib/nvoi/cli/delete/command.rb`
2. Create `lib/nvoi/cli/delete/steps/` directory
3. Extract each operation from `service/delete.rb` into separate step
4. Move `collect_volume_names` to command (shared state)
5. Delete `service/delete.rb`

---

## Estimated Effort

- **Lines to reorganize:** 235
- **Files created:** 8 (command + 7 steps)
- **Files deleted:** 1
- **DRY savings:** ~30 lines (shared hostname, merged tunnel+dns option)
