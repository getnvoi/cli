# 08 - CLI: Deploy Steps (Details)

## Priority: FIFTH (part of deploy)

Each step is a focused, single-responsibility class.

---

## Step 1: provision_network.rb (~50 lines)

**Source:** Extract from `deployer/infrastructure.rb`

**Does:**

- Find or create network
- Find or create firewall

```ruby
# cli/deploy/steps/provision_network.rb
module Nvoi
  module CLI
    module Deploy
      module Steps
        class ProvisionNetwork
          def initialize(config, provider, log)
            @config = config
            @provider = provider
            @log = log
          end

          def run
            @log.info "Provisioning network: %s", @config.network_name
            network = @provider.find_or_create_network(@config.network_name)

            @log.info "Provisioning firewall: %s", @config.firewall_name
            firewall = @provider.find_or_create_firewall(@config.firewall_name)

            { network: network, firewall: firewall }
          end
        end
      end
    end
  end
end
```

---

## Step 2: provision_server.rb (~80 lines)

**Source:** `steps/server_provisioner.rb` + `deployer/infrastructure.rb`

**Does:**

- Create servers for each group
- Wait for SSH ready
- Return main server IP

---

## Step 3: provision_volume.rb (~150 lines)

**Source:** `steps/volume_provisioner.rb`

**Does:**

- Collect all volumes needed (database, services, app)
- Create volumes via provider
- Attach to servers
- Mount via SSH (format if needed, add to fstab)

---

## Step 4: setup_k3s.rb (~400 lines)

**Source:** Merge `steps/k3s_provisioner.rb` + `steps/k3s_cluster_setup.rb`

**Does:**

- Wait for cloud-init
- Install K3s server on master
- Setup kubeconfig
- Setup in-cluster registry
- Setup NGINX ingress
- Install K3s agent on workers
- Label nodes
- Get cluster token

**Note:** This is the largest step. Consider keeping as single file with private methods, or split into:

- `setup_k3s/master.rb`
- `setup_k3s/worker.rb`
- `setup_k3s/registry.rb`

---

## Step 5: configure_tunnel.rb (~70 lines)

**Source:** `steps/tunnel_configurator.rb`

**Does:**

- For each app service with domain:
  - Create/find Cloudflare tunnel
  - Configure tunnel ingress
  - Create DNS CNAME record
- Return array of TunnelInfo

---

## Step 6: build_image.rb (~100 lines)

**Source:** `deployer/image_builder.rb` + parts of `remote/docker_manager.rb`

**Does:**

- Build Docker image locally
- Save to tar
- Rsync to remote server
- Import into containerd
- Tag image
- Push to in-cluster registry

---

## Step 7: deploy_database.rb (~80 lines)

**Source:** `steps/database_provisioner.rb` + `deployer/service_deployer.rb#deploy_database`

**Does:**

- Skip if SQLite (handled by app volumes)
- Deploy database secret (POSTGRES_USER, etc.)
- Deploy StatefulSet with hostPath volume
- Wait for database pod to be Running

---

## Step 8: deploy_service.rb (~300 lines)

**Source:** Merge `deployer/orchestrator.rb` + `deployer/service_deployer.rb`

**Does:**

- Deploy app secret (env vars)
- Deploy additional services (redis, etc.)
- Deploy app services (web, worker)
- Deploy cloudflared sidecars
- Verify traffic routing
- Run pre-run commands (migrations)

**Note:** Uses `External::Kubectl` for all manifest operations.

---

## Step 9: cleanup_images.rb (~40 lines)

**Source:** `deployer/cleaner.rb`

**Does:**

- List all images with prefix
- Keep newest N images
- Delete the rest

---

## Step Dependencies

```
provision_network ─┐
                   ├─► provision_server ─► provision_volume ─► setup_k3s
                   │
configure_tunnel ──┼─► build_image ─► deploy_service ─► cleanup_images
                   │
                   └── (parallel where possible)
```

---

## Common Patterns Across Steps

### Constructor Signature

All steps follow:

```ruby
def initialize(config, provider_or_deps, log)
```

### Return Values

- Most return `nil` (side effects only)
- Some return data for next step:
  - `provision_server` → main_server_ip
  - `configure_tunnel` → [TunnelInfo]
  - `provision_network` → { network:, firewall: }

### Error Handling

Steps raise specific errors. Command catches and logs.
