# 10 - CLI: Exec Command

## Priority: FIFTH (parallel with deploy/delete)

---

## Current State

| File | Lines | Purpose |
|------|-------|---------|
| `service/exec.rb` | 145 | ExecService - remote command execution |

---

## Target Structure

```
lib/nvoi/cli/exec/
└── command.rb          # Single file, no steps needed
```

---

## What Exec Does

Three modes:
1. **Single server:** `nvoi exec "ls -la"` → run on main server
2. **All servers:** `nvoi exec --all "ls -la"` → run on all servers in parallel
3. **Interactive:** `nvoi exec -i` → open SSH shell

---

## Target Implementation

```ruby
# cli/exec/command.rb
module Nvoi
  module CLI
    module Exec
      class Command
        def initialize(options)
          @options = options
          @log = Utils::Logger.new
        end

        def run(args)
          config = Utils::ConfigLoader.new.load(config_path)
          provider = External::Cloud.for(config)

          if @options[:interactive]
            open_shell(config, provider)
          elsif @options[:all]
            run_all(config, provider, args.join(" "))
          else
            run_single(config, provider, args.join(" "), @options[:server])
          end
        end

        private

        def run_single(config, provider, command, server_name)
          server = find_server(config, provider, server_name)
          ssh = External::SSH.new(server.public_ipv4, config.ssh_key_path)

          @log.info "Executing on %s: %s", server.name, command
          ssh.execute(command, stream: true)
          @log.success "Command completed"
        end

        def run_all(config, provider, command)
          servers = all_servers(config, provider)
          @log.info "Executing on %d servers", servers.size

          threads = servers.map do |server|
            Thread.new do
              ssh = External::SSH.new(server.public_ipv4, config.ssh_key_path)
              output = ssh.execute(command)
              [server.name, output]
            end
          end

          threads.each do |t|
            name, output = t.value
            output.lines.each { |line| puts "[#{name}] #{line}" }
          end
        end

        def open_shell(config, provider)
          server = find_server(config, provider, @options[:server])
          ssh = External::SSH.new(server.public_ipv4, config.ssh_key_path)
          ssh.open_shell
        end

        def find_server(config, provider, name)
          actual_name = resolve_server_name(config, name)
          provider.find_server(actual_name) or raise ServiceError, "server not found: #{actual_name}"
        end

        def resolve_server_name(config, name)
          return config.server_name if name == "main" || name.nil?
          # Parse "worker-1" → server_name("worker", 1)
          # ...
        end

        def all_servers(config, provider)
          config.deploy.application.servers.flat_map do |group, cfg|
            (1..cfg.count).map { |i| provider.find_server(config.namer.server_name(group, i)) }
          end.compact
        end
      end
    end
  end
end
```

---

## DRY Opportunities

### 1. Server Name Resolution
`resolve_server_name` logic is useful. Could go to `utils/namer.rb`:
```ruby
# utils/namer.rb
def resolve_server_reference(ref)
  # "main" → server_name for master
  # "worker-1" → server_name("worker", 1)
end
```

### 2. Server Collection
`all_servers` pattern could be a config method:
```ruby
# objects/config.rb
def each_server
  deploy.application.servers.each do |group, cfg|
    (1..cfg.count).each { |i| yield(group, i) }
  end
end
```

---

## Migration Steps

1. Create `lib/nvoi/cli/exec/command.rb`
2. Move logic from `service/exec.rb`
3. Extract `resolve_server_name` to `utils/namer.rb`
4. Delete `service/exec.rb`

---

## Estimated Effort

- **Lines to reorganize:** 145
- **Files created:** 1
- **Files deleted:** 1
- **Net change:** ~0 (simple move + namespace change)
