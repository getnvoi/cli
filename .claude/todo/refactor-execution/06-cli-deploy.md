# 06 - CLI Deploy Execution

## Reference
Read from: `/Users/ben/Desktop/nvoi-rb/lib/nvoi/`

## Build

Create `lib/nvoi/cli/deploy/command.rb`:
- Orchestrator from `service/deploy.rb`
- Uses `External::`, `Utils::`, `Objects::`

Create `lib/nvoi/cli/deploy/steps/`:

| File | Content (from reference) |
|------|--------------------------|
| `provision_network.rb` | From `deployer/infrastructure.rb` (network + firewall) |
| `provision_server.rb` | From `steps/server_provisioner.rb` |
| `provision_volume.rb` | From `steps/volume_provisioner.rb` |
| `setup_k3s.rb` | Merge `steps/k3s_provisioner.rb` + `steps/k3s_cluster_setup.rb` |
| `configure_tunnel.rb` | From `steps/tunnel_configurator.rb` |
| `build_image.rb` | From `deployer/image_builder.rb` |
| `deploy_database.rb` | From `steps/database_provisioner.rb` |
| `deploy_service.rb` | Merge `deployer/orchestrator.rb` + `deployer/service_deployer.rb` |
| `cleanup_images.rb` | From `deployer/cleaner.rb` |

Under `Nvoi::CLI::Deploy` namespace.

## Validate

- [ ] `ls lib/nvoi/cli/deploy/` shows command.rb + steps/
- [ ] `ls lib/nvoi/cli/deploy/steps/` shows 9 files
- [ ] command.rb orchestrates steps in correct order

## Test

```bash
cd /Users/ben/Desktop/nvoi-rb-refactor
ruby -e "require './lib/nvoi/cli/deploy/command'; p Nvoi::CLI::Deploy::Command"
```

## Commit

```bash
git add -A && git commit -m "Phase 6: Build cli/deploy/"
```
