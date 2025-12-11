# 11 - CLI: Credentials Commands

## Priority: FIFTH (parallel with others)

---

## Current State

| File                      | Lines | Purpose                         |
| ------------------------- | ----- | ------------------------------- |
| `cli.rb` (CredentialsCLI) | ~55   | Thor subcommand for credentials |
| `credentials/editor.rb`   | ~80   | Edit/show encrypted credentials |
| `credentials/manager.rb`  | ~150  | Load/save encrypted files       |
| `credentials/crypto.rb`   | ~100  | AES encryption                  |

**Total: ~385 lines**

---

## Target Structure

```
lib/nvoi/cli/credentials/
├── edit/
│   └── command.rb      # nvoi credentials edit
└── show/
    └── command.rb      # nvoi credentials show
```

Note: `crypto.rb` and `manager.rb` move to `utils/` (see 02-utils.md)

---

## What Each Command Does

### credentials edit

1. Load or create credentials file
2. Decrypt to temp file
3. Open in $EDITOR
4. Validate YAML on save
5. Re-encrypt
6. Update .gitignore if first run

### credentials show

1. Load credentials file
2. Decrypt
3. Print to stdout

---

## Target Implementation

```ruby
# cli/credentials/edit/command.rb
module Nvoi
  module CLI
    module Credentials
      module Edit
        class Command
          def initialize(options)
            @options = options
            @log = Utils::Logger.new
          end

          def run
            working_dir = resolve_working_dir
            store = Utils::CredentialStore.new(working_dir, @options[:credentials], @options[:master_key])

            if store.exists?
              edit_existing(store)
            else
              create_new(store)
            end
          end

          private

          def edit_existing(store)
            content = store.read
            new_content = open_in_editor(content)
            validate_yaml!(new_content)
            store.write(new_content)
            @log.success "Credentials updated"
          end

          def create_new(store)
            @log.info "Creating new credentials file"
            template = default_template
            new_content = open_in_editor(template)
            validate_yaml!(new_content)
            store.write(new_content)
            store.update_gitignore
            @log.success "Credentials created"
            @log.warning "Keep your master key safe!"
          end

          def open_in_editor(content)
            # Write to temp file, exec $EDITOR, read back
          end

          def validate_yaml!(content)
            YAML.safe_load(content)
          rescue Psych::SyntaxError => e
            raise ConfigError, "Invalid YAML: #{e.message}"
          end
        end
      end
    end
  end
end
```

```ruby
# cli/credentials/show/command.rb
module Nvoi
  module CLI
    module Credentials
      module Show
        class Command
          def initialize(options)
            @options = options
          end

          def run
            working_dir = resolve_working_dir
            store = Utils::CredentialStore.new(working_dir, @options[:credentials], @options[:master_key])
            puts store.read
          end
        end
      end
    end
  end
end
```

---

## DRY Opportunities

### 1. Merge Crypto + Manager → CredentialStore

Already planned in 02-utils.md. Single class:

```ruby
# utils/crypto.rb
class CredentialStore
  def initialize(working_dir, enc_path = nil, key_path = nil)
  def exists? → bool
  def read → String
  def write(content)
  def update_gitignore
end
```

### 2. Remove Editor Class

Current `credentials/editor.rb` is thin wrapper. Logic goes directly into command.

### 3. YAML Validation

Move to utils for reuse:

```ruby
# utils/config_loader.rb
def self.validate_yaml!(content)
  YAML.safe_load(content, permitted_classes: [Symbol])
end
```

---

## Migration Steps

1. Move `credentials/crypto.rb` + `credentials/manager.rb` → `utils/crypto.rb` (02-utils.md)
2. Create `lib/nvoi/cli/credentials/edit/command.rb`
3. Create `lib/nvoi/cli/credentials/show/command.rb`
4. Move editor logic into `edit/command.rb`
5. Delete `credentials/editor.rb`
6. Update `cli.rb` to route to new commands

---

## Estimated Effort

- **Lines to reorganize:** ~385
- **Files created:** 2
- **Files deleted:** 3 (`editor.rb`, `manager.rb`, `crypto.rb` → merged to utils)
- **Net reduction:** ~50 lines (removed wrapper, merged classes)
