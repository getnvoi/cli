# Refactor Overview

## Target Structure

```
lib/nvoi/
├── cli.rb                              # Thor routing only (~50 lines)
│
├── cli/
│   ├── deploy/
│   │   ├── command.rb
│   │   └── steps/
│   │       ├── provision_network.rb
│   │       ├── provision_server.rb
│   │       ├── provision_volume.rb
│   │       ├── setup_k3s.rb
│   │       ├── configure_tunnel.rb
│   │       ├── build_image.rb
│   │       ├── deploy_service.rb
│   │       └── cleanup_images.rb
│   │
│   ├── delete/
│   │   ├── command.rb
│   │   └── steps/
│   │       ├── teardown_tunnel.rb
│   │       ├── teardown_dns.rb
│   │       ├── detach_volumes.rb
│   │       ├── teardown_server.rb
│   │       ├── teardown_volume.rb
│   │       ├── teardown_firewall.rb
│   │       └── teardown_network.rb
│   │
│   ├── exec/
│   │   └── command.rb
│   │
│   └── credentials/
│       ├── edit/
│       │   └── command.rb
│       └── show/
│           └── command.rb
│
├── external/
│   ├── cloud/
│   │   ├── base.rb
│   │   ├── hetzner.rb
│   │   ├── aws.rb
│   │   ├── scaleway.rb
│   │   └── factory.rb
│   ├── dns/
│   │   └── cloudflare.rb
│   ├── ssh.rb
│   ├── kubectl.rb
│   └── containerd.rb
│
├── objects/
│   ├── server.rb
│   ├── network.rb
│   ├── firewall.rb
│   ├── volume.rb
│   ├── tunnel.rb
│   ├── dns.rb
│   ├── service_spec.rb
│   └── config.rb
│
└── utils/
    ├── namer.rb
    ├── env_resolver.rb
    ├── config_loader.rb
    ├── crypto.rb
    ├── templates.rb
    ├── logger.rb
    ├── constants.rb
    ├── errors.rb
    └── retry.rb
```

---

## Refactor Order

| #   | File                       | Description               | Depends On      |
| --- | -------------------------- | ------------------------- | --------------- |
| 01  | objects.md                 | Domain entities (Structs) | Nothing         |
| 02  | utils.md                   | Shared helpers            | Objects         |
| 03  | external-cloud.md          | Cloud provider adapters   | Objects, Utils  |
| 04  | external-dns.md            | Cloudflare adapter        | Objects, Utils  |
| 05  | external.md                | SSH, kubectl, containerd  | Objects, Utils  |
| 06  | cli.md                     | Thor router               | Commands        |
| 07  | cli-deploy-command.md      | Deploy orchestration      | External, Utils |
| 08  | cli-deploy-steps.md        | Deploy step details       | External, Utils |
| 09  | cli-delete-command.md      | Delete orchestration      | External, Utils |
| 10  | cli-exec-command.md        | Exec command              | External, Utils |
| 11  | cli-credentials-command.md | Credentials commands      | Utils           |

---

## Line Count Summary

### Current State (~4200 lines)

| Category                          | Lines |
| --------------------------------- | ----- |
| Config types + loading            | ~550  |
| Credentials                       | ~330  |
| Providers                         | ~1380 |
| Cloudflare                        | ~350  |
| Remote (SSH, Docker, Volume)      | ~430  |
| K8s (templates, renderer)         | ~75   |
| Steps                             | ~750  |
| Deployer                          | ~580  |
| Service (CLI entry)               | ~460  |
| Utils (logger, constants, errors) | ~200  |
| CLI                               | ~190  |

### Target State (~3800 lines)

| Category         | Lines | Change           |
| ---------------- | ----- | ---------------- |
| objects/         | ~400  | consolidated     |
| utils/           | ~600  | merged           |
| external/        | ~1000 | merged providers |
| cli/deploy/      | ~1200 | flattened        |
| cli/delete/      | ~300  | separated        |
| cli/exec/        | ~150  | simplified       |
| cli/credentials/ | ~100  | simplified       |
| cli.rb           | ~50   | routing only     |

**Net reduction: ~400 lines (10%)**

---

## DRY Wins

1. **Hostname builder** - 3 duplications → 1 in `utils/namer.rb`
2. **Provider + Client merge** - 4 files → 3 files
3. **TunnelManager absorption** - eliminated wrapper
4. **Config loader + SSH key merge** - 2 files → 1 file
5. **Crypto + Manager merge** - 2 files → 1 file
6. **Templates + Binding merge** - 2 files → 1 file
7. **Thin wrapper removal** - `ApplicationDeployer`, `Editor` → gone
8. **Struct consolidation** - scattered → `objects/`

---

## Migration Strategy

### Phase 1: Foundation (01-02)

Create `objects/` and `utils/`. No breaking changes yet.
Other code keeps working, just uses new locations.

### Phase 2: External Adapters (03-05)

Move and merge providers. Update imports.
Still backward compatible with old namespaces via aliases if needed.

### Phase 3: Commands (07-11)

Create new command structure.
Old `service/*.rb` files still work during transition.

### Phase 4: Router (06)

Switch `cli.rb` to new commands.
Delete old files.

### Phase 5: Cleanup

- Remove empty directories
- Remove old requires from `lib/nvoi.rb`
- Update tests
