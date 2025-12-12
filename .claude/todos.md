# Onboard Wizard: Multi-Server & Volume Validation

## Overview

Extend the onboard wizard to support multi-server setups and add validation for volume/server constraints.

---

## Part 1: Volume/Server Validation

### File: `lib/nvoi/objects/configuration.rb`

Add validation in `validate_servers_and_references` method (after line ~108):

```ruby
# Validate volume mount constraints
def validate_volume_mounts(app, servers)
  app.app.each do |app_name, app_config|
    next if app_config.mounts.nil? || app_config.mounts.empty?

    # Can't mount volumes when running on multiple servers
    if app_config.servers.size > 1
      raise Errors::ConfigValidationError,
        "app.#{app_name}: cannot mount volumes when running on multiple servers (#{app_config.servers.join(', ')})"
    end

    # Can't mount volumes on multi-instance server (count > 1)
    app_config.servers.each do |server_ref|
      server = servers[server_ref]
      next unless server

      if server.count && server.count > 1
        raise Errors::ConfigValidationError,
          "app.#{app_name}: cannot mount volumes on multi-instance server '#{server_ref}' (count: #{server.count})"
      end

      # Verify volume exists on server
      app_config.mounts.each_key do |vol_name|
        unless server.volumes&.key?(vol_name)
          available = server.volumes&.keys&.join(", ") || "none"
          raise Errors::ConfigValidationError,
            "app.#{app_name}: mount '#{vol_name}' not found on server '#{server_ref}' (available: #{available})"
        end
      end
    end
  end

  # Database always needs volume, validate server constraints
  return unless app.database

  app.database.servers.each do |server_ref|
    server = servers[server_ref]
    next unless server

    if server.count && server.count > 1
      raise Errors::ConfigValidationError,
        "database: cannot run on multi-instance server '#{server_ref}' (count: #{server.count}) - volumes can't multi-attach"
    end
  end
end
```

### File: `test/nvoi/objects/config_test.rb`

Add tests:

```ruby
def test_validates_no_volume_mount_on_multi_instance_server
  config_data = {
    "application" => {
      "name" => "test",
      "servers" => {
        "workers" => { "count" => 3, "volumes" => { "data" => { "size" => 10 } } }
      },
      "app" => {
        "web" => { "servers" => ["workers"], "mounts" => { "data" => "/app/data" } }
      }
    }
  }

  error = assert_raises(Nvoi::Errors::ConfigValidationError) do
    Nvoi::Objects::Configuration.new(config_data)
  end
  assert_match(/cannot mount volumes on multi-instance server/, error.message)
end

def test_validates_no_volume_mount_on_multiple_servers
  config_data = {
    "application" => {
      "name" => "test",
      "servers" => {
        "server1" => { "master" => true, "volumes" => { "data" => { "size" => 10 } } },
        "server2" => { "volumes" => { "data" => { "size" => 10 } } }
      },
      "app" => {
        "web" => { "servers" => ["server1", "server2"], "mounts" => { "data" => "/app/data" } }
      }
    }
  }

  error = assert_raises(Nvoi::Errors::ConfigValidationError) do
    Nvoi::Objects::Configuration.new(config_data)
  end
  assert_match(/cannot mount volumes when running on multiple servers/, error.message)
end

def test_validates_database_not_on_multi_instance_server
  config_data = {
    "application" => {
      "name" => "test",
      "servers" => {
        "workers" => { "master" => true, "count" => 2, "volumes" => { "pg_data" => { "size" => 10 } } }
      },
      "database" => {
        "servers" => ["workers"],
        "adapter" => "postgres",
        "secrets" => { "POSTGRES_DB" => "x", "POSTGRES_USER" => "x", "POSTGRES_PASSWORD" => "x" }
      }
    }
  }

  error = assert_raises(Nvoi::Errors::ConfigValidationError) do
    Nvoi::Objects::Configuration.new(config_data)
  end
  assert_match(/database: cannot run on multi-instance server/, error.message)
end

def test_validates_mount_volume_exists_on_server
  config_data = {
    "application" => {
      "name" => "test",
      "servers" => {
        "main" => { "master" => true }  # no volumes defined
      },
      "app" => {
        "web" => { "servers" => ["main"], "mounts" => { "data" => "/app/data" } }
      }
    }
  }

  error = assert_raises(Nvoi::Errors::ConfigValidationError) do
    Nvoi::Objects::Configuration.new(config_data)
  end
  assert_match(/mount 'data' not found on server 'main'/, error.message)
end
```

---

## Part 2: Onboard Wizard - Server Setup

### File: `lib/nvoi/cli/onboard/command.rb`

#### 2.1 Add `step_servers` after `step_compute_provider`

```ruby
def step_servers
  puts
  puts section("Server Configuration")

  mode = @prompt.select("Server setup:") do |menu|
    menu.choice "Single server (recommended for small apps)", :single
    menu.choice "Multi-server (master + workers)", :multi
  end

  case mode
  when :single
    setup_single_server
  when :multi
    setup_multi_server
  end
end

def setup_single_server
  @data["application"]["servers"] = {
    "main" => { "master" => true, "count" => 1 }
  }
  @server_mode = :single
end

def setup_multi_server
  @data["application"]["servers"] = {}

  # Master server (control plane)
  puts
  puts pastel.dim("Master server runs k3s control plane")
  master_type = prompt_server_type("Master server type:")
  @data["application"]["servers"]["master"] = {
    "master" => true,
    "count" => 1,
    "type" => master_type
  }

  # Worker servers
  puts
  puts pastel.dim("Worker servers run your apps")
  worker_type = prompt_server_type("Worker server type:")
  worker_count = @prompt.ask("Number of workers:", default: "2", convert: :int)
  @data["application"]["servers"]["workers"] = {
    "count" => worker_count,
    "type" => worker_type
  }

  # Dedicated database server?
  if @prompt.yes?("Dedicated database server? (recommended for production)")
    db_type = prompt_server_type("Database server type:")
    @data["application"]["servers"]["database"] = {
      "count" => 1,
      "type" => db_type
    }
    @dedicated_db_server = true
  else
    @dedicated_db_server = false
  end

  @server_mode = :multi
end

def prompt_server_type(message)
  # Use cached server types from compute provider setup
  return @prompt.ask(message) unless @server_types

  choices = @server_types.map do |t|
    price = t[:price] ? " - #{t[:price]}/mo" : ""
    { name: "#{t[:name]} (#{t[:cores]} vCPU, #{t[:memory] / 1024}GB#{price})", value: t[:name] }
  end
  @prompt.select(message, choices, per_page: 10)
end
```

#### 2.2 Update `step_apps` - Add replicas and server selection

```ruby
def step_apps
  puts
  puts section("Applications")

  @data["application"]["app"] ||= {}

  loop do
    name = @prompt.ask("App name:") { |q| q.required true }
    command = @prompt.ask("Run command (optional, leave blank for Docker entrypoint):")
    port = @prompt.ask("Port (optional, leave blank for background workers):")
    port = port.to_i if port && !port.to_s.empty?

    app_config = { "servers" => default_app_servers }
    app_config["command"] = command unless command.to_s.empty?
    app_config["port"] = port if port && port > 0

    # Replicas (only for web-facing apps)
    if port && port > 0
      replicas = @prompt.ask("Replicas:", default: "2", convert: :int)
      app_config["replicas"] = replicas if replicas && replicas > 0
    end

    # Server selection (only for multi-server)
    if @server_mode == :multi
      app_config["servers"] = prompt_server_selection(name, has_mounts: false)
    end

    # Domain selection only if port is set (web-facing) and Cloudflare configured
    if port && port > 0 && @cloudflare_zones&.any?
      domain, subdomain = prompt_domain_selection
      if domain
        app_config["domain"] = domain
        app_config["subdomain"] = subdomain unless subdomain.to_s.empty?
      end
    end

    pre_run = @prompt.ask("Pre-run command (e.g. migrations):")
    app_config["pre_run_command"] = pre_run unless pre_run.to_s.empty?

    @data["application"]["app"][name] = app_config

    break unless @prompt.yes?("Add another app?")
  end
end

def default_app_servers
  case @server_mode
  when :single then ["main"]
  when :multi then ["workers"]
  else ["main"]
  end
end

def prompt_server_selection(context, has_mounts: false)
  servers = @data["application"]["servers"].keys

  if has_mounts
    # Filter to single-instance servers only
    servers = servers.select do |name|
      count = @data["application"]["servers"][name]["count"] || 1
      count == 1
    end

    if servers.empty?
      error("No single-instance servers available for volume mounts")
      error("Volume mounts require count: 1 server (volumes can't multi-attach)")
      return ["main"]
    end

    # Single select only
    selected = @prompt.select("Server for #{context} (volumes require single server):", servers)
    [selected]
  else
    # Multi-select allowed for stateless apps
    @prompt.multi_select("Servers for #{context}:", servers, min: 1)
  end
end
```

#### 2.3 Update `step_database` - Server selection for multi-server

```ruby
def step_database
  puts
  puts section("Database")

  adapter = @prompt.select("Database:") do |menu|
    menu.choice "PostgreSQL", "postgres"
    menu.choice "MySQL", "mysql"
    menu.choice "SQLite", "sqlite3"
    menu.choice "None (skip)", nil
  end

  return unless adapter

  # Database server selection for multi-server mode
  db_servers = if @server_mode == :multi
    if @dedicated_db_server
      ["database"]  # Use dedicated db server
    else
      prompt_server_selection("database", has_mounts: true)
    end
  else
    ["main"]
  end

  db_config = {
    "servers" => db_servers,
    "adapter" => adapter
  }

  # Add volume to the database server
  db_server_name = db_servers.first
  @data["application"]["servers"][db_server_name]["volumes"] ||= {}

  case adapter
  when "postgres"
    db_name = @prompt.ask("Database name:", default: "#{@data["application"]["name"]}_production")
    user = @prompt.ask("Database user:", default: @data["application"]["name"])
    password = @prompt.mask("Database password:") { |q| q.required true }

    db_config["secrets"] = {
      "POSTGRES_DB" => db_name,
      "POSTGRES_USER" => user,
      "POSTGRES_PASSWORD" => password
    }

    @data["application"]["servers"][db_server_name]["volumes"]["postgres_data"] = { "size" => 10 }

  when "mysql"
    db_name = @prompt.ask("Database name:", default: "#{@data["application"]["name"]}_production")
    user = @prompt.ask("Database user:", default: @data["application"]["name"])
    password = @prompt.mask("Database password:") { |q| q.required true }

    db_config["secrets"] = {
      "MYSQL_DATABASE" => db_name,
      "MYSQL_USER" => user,
      "MYSQL_PASSWORD" => password
    }

    @data["application"]["servers"][db_server_name]["volumes"]["mysql_data"] = { "size" => 10 }

  when "sqlite3"
    path = @prompt.ask("Database path:", default: "/app/data/production.sqlite3")
    db_config["path"] = path
    db_config["mount"] = { "data" => "/app/data" }

    @data["application"]["servers"][db_server_name]["volumes"]["sqlite_data"] = { "size" => 10 }
  end

  @data["application"]["database"] = db_config
end
```

#### 2.4 Update `run` method

```ruby
def run
  show_welcome

  step_app_name
  step_compute_provider
  step_servers          # NEW - after compute provider
  step_domain_provider
  step_apps             # Updated - replicas + server selection
  step_database         # Updated - server selection
  step_env

  summary_loop

  show_next_steps
rescue TTY::Reader::InputInterrupt
  puts "\n\nSetup cancelled."
  exit 1
end
```

#### 2.5 Update `show_summary` for multi-server

```ruby
def show_summary
  # ... existing code ...

  # Server info
  server_info = @data["application"]["servers"].map do |name, cfg|
    count = cfg["count"] || 1
    type = cfg["type"] || "default"
    master = cfg["master"] ? " (master)" : ""
    "#{name}: #{count}x #{type}#{master}"
  end.join(", ")

  rows = [
    ["Application", @data["application"]["name"]],
    ["Provider", "#{provider_name} (#{provider_info})"],
    ["Servers", server_info],  # NEW
    ["Domain", "Cloudflare #{domain_ok}"],
    ["Apps", app_list],
    ["Database", db],
    ["Env/Secrets", "#{env_count} variables"]
  ]

  # ... rest of method ...
end
```

---

## Part 3: Test Updates

### File: `test/cli/onboard/test_command.rb`

```ruby
def test_single_server_mode
  prompt = TTY::Prompt::Test.new

  prompt.input << "myapp\n"
  prompt.input << "\r"                # hetzner
  prompt.input << "token\n"
  prompt.input << "\r"                # server type
  prompt.input << "\r"                # location
  prompt.input << "\r"                # Single server mode
  prompt.input << "n\n"               # no cloudflare
  prompt.input << "web\n"
  prompt.input << "\n"                # no command
  prompt.input << "3000\n"            # port
  prompt.input << "2\n"               # replicas
  prompt.input << "\n"                # no pre-run
  prompt.input << "n\n"               # no more apps
  prompt.input << "\e[B\e[B\e[B\r"    # no database
  prompt.input << "\e[B\e[B\r"        # done with env
  prompt.input << "\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\r"  # Cancel
  prompt.input << "y\n"
  prompt.input.rewind

  with_hetzner_mock do
    cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
    cmd.run
  end

  output = prompt.output.string
  assert_match(/Single server/, output)
end

def test_multi_server_mode
  prompt = TTY::Prompt::Test.new

  prompt.input << "myapp\n"
  prompt.input << "\r"                # hetzner
  prompt.input << "token\n"
  prompt.input << "\r"                # server type
  prompt.input << "\r"                # location
  prompt.input << "\e[B\r"            # Multi-server mode
  prompt.input << "\r"                # master type
  prompt.input << "\r"                # worker type
  prompt.input << "2\n"               # worker count
  prompt.input << "y\n"               # dedicated db server
  prompt.input << "\r"                # db server type
  prompt.input << "n\n"               # no cloudflare
  prompt.input << "web\n"
  prompt.input << "\n"
  prompt.input << "3000\n"
  prompt.input << "2\n"               # replicas
  prompt.input << " \r"               # select workers (space to select, enter to confirm)
  prompt.input << "\n"
  prompt.input << "n\n"
  prompt.input << "\r"                # postgres
  prompt.input << "mydb\n"
  prompt.input << "myuser\n"
  prompt.input << "mypass\n"
  prompt.input << "\e[B\e[B\r"        # done with env
  prompt.input << "\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\r"
  prompt.input << "y\n"
  prompt.input.rewind

  with_hetzner_mock do
    cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
    cmd.run
  end

  output = prompt.output.string
  assert_match(/master/, output)
  assert_match(/workers/, output)
  assert_match(/database/, output)
end
```

---

## Implementation Order

1. [ ] **Part 1: Validation** - Add volume/server validation to configuration.rb + tests
2. [ ] **Part 2.1: step_servers** - Add server setup step
3. [ ] **Part 2.2: step_apps update** - Add replicas + server selection
4. [ ] **Part 2.3: step_database update** - Add server selection
5. [ ] **Part 2.4: run method** - Wire up new step
6. [ ] **Part 2.5: show_summary** - Show server info
7. [ ] **Part 3: Tests** - Add tests for new flows

---

## Notes

- Keep `@server_types` cached from compute provider setup for reuse
- `@server_mode` tracks :single vs :multi for conditional prompts
- `@dedicated_db_server` tracks if user chose dedicated db server
- Volume auto-creation happens in step_database based on selected server
- Multi-select uses `multi_select` with `min: 1`
- Single-server mode remains the default (recommended path)
