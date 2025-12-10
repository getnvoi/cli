# 05 - External: SSH, Kubectl, Containerd

## Priority: THIRD (parallel with cloud/dns)

---

## Current State

| File                       | Lines | Purpose                      |
| -------------------------- | ----- | ---------------------------- |
| `remote/ssh_executor.rb`   | 73    | SSH command execution        |
| `remote/docker_manager.rb` | 204   | Docker/containerd operations |
| `remote/volume_manager.rb` | 104   | Volume mount operations      |
| `k8s/renderer.rb`          | 45    | kubectl apply wrapper        |

**Total: ~426 lines across 4 files**

---

## Target Structure

```
lib/nvoi/external/
├── ssh.rb              # SSH executor
├── kubectl.rb          # kubectl wrapper (from k8s/renderer.rb)
└── containerd.rb       # containerd/Docker operations (from docker_manager.rb + volume_manager.rb)
```

---

## What Each Does

### SSH Executor (`remote/ssh_executor.rb`)

- `execute(command, stream: false)` → String
- `execute_quiet(command)` → nil (ignore errors)
- `open_shell` → exec into SSH

### Docker Manager (`remote/docker_manager.rb`)

- `create_network(name)`
- `build_image(path, tag, cache_from)` → local build, rsync, ctr import
- `run_container(opts)`
- `exec(container, command)`
- `wait_for_health(opts)`
- `container_status(name)`, `container_logs(name, lines)`
- `stop_container(name)`, `remove_container(name)`
- `list_containers(filter)`, `list_images(filter)`
- `cleanup_old_images(prefix, keep_tags)`
- `container_running?(name)`
- `setup_cloudflared(network, token, name)`

### Volume Manager (`remote/volume_manager.rb`)

- `mount(opts)` → format + mount + fstab
- `unmount(mount_path)`
- `mounted?(mount_path)`
- `remove_from_fstab(mount_path)`

### K8s Renderer (`k8s/renderer.rb`)

- `render_template(name, data)` → String
- `apply_manifest(ssh, template_name, data)` → kubectl apply
- `wait_for_deployment(ssh, name, namespace, timeout)`

---

## DRY Opportunities

### 1. Rename docker_manager → containerd

It's not really Docker anymore. It uses `ctr` (containerd). Name it accurately:

```ruby
# external/containerd.rb
class Containerd
  def initialize(ssh) ... end
  def build_and_import(path, tag) ... end
  def list_images(filter) ... end
  def cleanup_images(prefix, keep_tags) ... end
end
```

### 2. Extract Volume Logic

Volume mounting is separate from container runtime. Could stay in containerd or be separate.
Decision: Keep in containerd since it's all "server-side stuff via SSH".

### 3. Simplify K8s Renderer

Move template rendering to `utils/templates.rb`. Keep only kubectl operations:

```ruby
# external/kubectl.rb
class Kubectl
  def initialize(ssh) ... end
  def apply(manifest) ... end
  def wait_for_deployment(name, namespace, timeout) ... end
  def wait_for_statefulset(name, namespace, timeout) ... end
  def get_pod_name(label) ... end
  def exec(pod, command) ... end
end
```

### 4. SSH as Dependency

All external adapters that run on remote servers need SSH:

- `Containerd.new(ssh)`
- `Kubectl.new(ssh)`
- `VolumeManager.new(ssh)` (if kept separate)

This is correct. SSH is the transport, others are domain-specific.

---

## Migration Steps

1. Move `remote/ssh_executor.rb` → `external/ssh.rb`
2. Rename `remote/docker_manager.rb` → `external/containerd.rb`
3. Merge `remote/volume_manager.rb` into `external/containerd.rb` (or keep separate)
4. Extract kubectl operations from `k8s/renderer.rb` → `external/kubectl.rb`
5. Move template rendering to `utils/templates.rb` (already planned in 02-utils.md)
6. Update namespace from `Remote::SSHExecutor` to `External::SSH`

---

## Estimated Effort

- **Lines to consolidate:** ~426
- **Files created:** 3
- **Files deleted:** 4
- **DRY savings:** ~30 lines (simplified renderer, naming cleanup)
