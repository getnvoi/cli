# 06 - CLI Entry Point (Thor Routing)

## Priority: FOURTH

CLI depends on all command implementations.

---

## Current State

| File     | Lines | Purpose                                   |
| -------- | ----- | ----------------------------------------- |
| `cli.rb` | 191   | Thor commands + CredentialsCLI subcommand |

---

## Target Structure

```
lib/nvoi/
└── cli.rb              # Thor routing only (~50 lines)
```

---

## What CLI Currently Does

1. **Thor setup** - class options, exit behavior
2. **Command definitions** - `deploy`, `delete`, `exec`, `credentials`
3. **Config path resolution** - `resolve_config_path`, `resolve_working_dir`
4. **Instantiate services** - creates `DeployService`, `DeleteService`, etc.

---

## Target: Thin Router

CLI should ONLY:

1. Define Thor commands
2. Parse options
3. Delegate to `cli/<command>/command.rb`

```ruby
# cli.rb
module Nvoi
  class CLI < Thor
    class_option :config, aliases: "-c", default: "deploy.enc"
    class_option :dir, aliases: "-d", default: "."

    desc "deploy", "Deploy application"
    option :dockerfile_path
    def deploy
      require_relative "cli/deploy/command"
      CLI::Deploy::Command.new(options).run
    end

    desc "delete", "Delete infrastructure"
    def delete
      require_relative "cli/delete/command"
      CLI::Delete::Command.new(options).run
    end

    desc "exec [COMMAND...]", "Execute command on server"
    option :server, default: "main"
    option :all, type: :boolean
    option :interactive, aliases: "-i", type: :boolean
    def exec(*args)
      require_relative "cli/exec/command"
      CLI::Exec::Command.new(options).run(args)
    end

    desc "credentials SUBCOMMAND", "Manage credentials"
    subcommand "credentials", CLI::Credentials
  end

  class CLI::Credentials < Thor
    desc "edit", "Edit encrypted credentials"
    def edit
      require_relative "cli/credentials/edit/command"
      CLI::Credentials::Edit::Command.new(options).run
    end

    desc "show", "Show decrypted credentials"
    def show
      require_relative "cli/credentials/show/command"
      CLI::Credentials::Show::Command.new(options).run
    end
  end
end
```

---

## DRY Opportunities

### 1. Move Logic to Commands

All the `resolve_config_path`, validation, service instantiation moves INTO each command.

### 2. Lazy Requires

Use `require_relative` inside methods. Faster CLI startup, only loads what's needed.

### 3. CredentialsCLI → Nested Class

Currently separate class, can be nested under CLI.

---

## Migration Steps

1. Create command files first (07-10)
2. Strip `cli.rb` down to routing only
3. Move `CredentialsCLI` inline as `CLI::Credentials`
4. Add lazy requires for each command

---

## Estimated Effort

- **Lines after refactor:** ~50 (down from 191)
- **Logic moved to:** `cli/*/command.rb` files
- **DRY savings:** 141 lines moved (not deleted, redistributed)
