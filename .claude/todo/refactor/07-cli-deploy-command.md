# 07 - CLI: Deploy Command

## Priority: FIFTH

Depends on external adapters, utils, objects.

---

## Current State

| File                | Lines | Purpose                     |
| ------------------- | ----- | --------------------------- |
| `service/deploy.rb` | 81    | DeployService orchestration |

---

## Target Structure

```
lib/nvoi/cli/deploy/
├── command.rb          # Entry point + step orchestration
└── steps/
    ├── provision_network.rb
    ├── provision_server.rb
    ├── provision_volume.rb
    ├── setup_k3s.rb
    ├── configure_tunnel.rb
    ├── build_image.rb
    ├── deploy_database.rb
    ├── deploy_service.rb
    └── cleanup_images.rb
```

---

## What Deploy Does (Current Flow)

```
1. Load config
2. Init provider
3. Validate provider config
4. provision_server:
   a. ServerProvisioner.run → provisions network, firewall, servers
   b. VolumeProvisioner.run → creates/attaches/mounts volumes
   c. K3sClusterSetup.run → installs K3s on master + workers
5. configure_tunnels:
   a. TunnelConfigurator.run → creates Cloudflare tunnels + DNS
6. deploy_application:
   a. Orchestrator.run:
      - Acquire lock
      - ImageBuilder.build_and_push
      - Push to registry
      - ServiceDeployer.deploy_app_secret
      - ServiceDeployer.deploy_database
      - ServiceDeployer.deploy_service (for each service)
      - ServiceDeployer.deploy_app_service (for each app)
      - ServiceDeployer.deploy_cloudflared
      - ServiceDeployer.verify_traffic_switchover
      - Cleaner.cleanup_old_images
      - Release lock
```

---

## Target Flow (Simplified)

```ruby
# cli/deploy/command.rb
class Command
  def run
    config = Utils::ConfigLoader.new.load(config_path)
    provider = External::Cloud.for(config)
    log = Utils::Logger.new

    Steps::ProvisionNetwork.new(config, provider, log).run
    Steps::ProvisionServer.new(config, provider, log).run
    Steps::ProvisionVolume.new(config, provider, log).run
    Steps::SetupK3s.new(config, provider, log).run
    tunnels = Steps::ConfigureTunnel.new(config, log).run
    Steps::BuildImage.new(config, log).run
    Steps::DeployService.new(config, tunnels, log).run
    Steps::CleanupImages.new(config, log).run
  end
end
```

---

## DRY Opportunities

### 1. Flatten the Hierarchy

Current: `DeployService` → `Steps::*` → `Deployer::*`
Target: `Command` → `Steps::*` directly

Kill `Deployer::Orchestrator`. Its logic moves into `Steps::DeployService`.

### 2. Remove Thin Wrappers

`Steps::ApplicationDeployer` is just:

```ruby
def run
  orchestrator = Deployer::Orchestrator.new(@config, @provider, @log)
  orchestrator.run(@server_ip, @tunnels, @working_dir)
end
```

Delete it. Put that logic in `Steps::DeployService`.

### 3. Consolidate ServiceDeployer

`Deployer::ServiceDeployer` (312 lines) does too much:

- Deploy app secret
- Deploy app service
- Deploy database
- Deploy generic service
- Deploy cloudflared
- Verify traffic
- Run pre-run commands

Split into focused steps or keep as internal helper in `Steps::DeployService`.

### 4. Lock Management

Deployment lock is in `Orchestrator`. Move to `Command`:

```ruby
def run
  acquire_lock(ssh)
  # ... steps ...
ensure
  release_lock(ssh)
end
```

---

## Migration Steps

1. Create `lib/nvoi/cli/deploy/command.rb`
2. Create `lib/nvoi/cli/deploy/steps/` directory
3. Move `steps/server_provisioner.rb` → `cli/deploy/steps/provision_server.rb`
4. Move `steps/volume_provisioner.rb` → `cli/deploy/steps/provision_volume.rb`
5. Merge `steps/k3s_cluster_setup.rb` + `steps/k3s_provisioner.rb` → `cli/deploy/steps/setup_k3s.rb`
6. Move `steps/tunnel_configurator.rb` → `cli/deploy/steps/configure_tunnel.rb`
7. Move `deployer/image_builder.rb` → `cli/deploy/steps/build_image.rb`
8. Merge `deployer/orchestrator.rb` + `deployer/service_deployer.rb` → `cli/deploy/steps/deploy_service.rb`
9. Move `deployer/cleaner.rb` → `cli/deploy/steps/cleanup_images.rb`
10. Extract network/firewall from ServerProvisioner → `cli/deploy/steps/provision_network.rb`
11. Delete old files: `service/deploy.rb`, `deployer/orchestrator.rb`, `steps/application_deployer.rb`

---

## Estimated Effort

**Files involved:**

- `service/deploy.rb` (81 lines)
- `steps/server_provisioner.rb` (44 lines)
- `steps/volume_provisioner.rb` (155 lines)
- `steps/k3s_provisioner.rb` (352 lines)
- `steps/k3s_cluster_setup.rb` (106 lines)
- `steps/tunnel_configurator.rb` (67 lines)
- `steps/application_deployer.rb` (27 lines)
- `deployer/orchestrator.rb` (147 lines)
- `deployer/infrastructure.rb` (127 lines)
- `deployer/image_builder.rb` (24 lines)
- `deployer/service_deployer.rb` (312 lines)
- `deployer/cleaner.rb` (37 lines)

**Total: ~1479 lines to reorganize**

- **Files created:** 9 (command.rb + 8 steps)
- **Files deleted:** 12
- **DRY savings:** ~150 lines (removed wrappers, flattened hierarchy)
