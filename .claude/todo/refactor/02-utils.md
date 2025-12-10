# 02 - Utils (Shared Helpers)

## Priority: SECOND

Utils depend only on Objects. Everything else uses them.

---

## Current State

| Utility           | Current Location         | Lines | Purpose                            |
| ----------------- | ------------------------ | ----- | ---------------------------------- |
| `ResourceNamer`   | `config/naming.rb`       | 197   | Generate consistent resource names |
| `EnvResolver`     | `config/env_resolver.rb` | 64    | Merge env vars from config         |
| `SSHKeyLoader`    | `config/ssh_keys.rb`     | ~80   | Load SSH keys from config          |
| `ConfigLoader`    | `config/loader.rb`       | 103   | Load and parse config file         |
| `Crypto`          | `credentials/crypto.rb`  | ~100  | AES encryption/decryption          |
| `Manager`         | `credentials/manager.rb` | ~150  | Credential file management         |
| `Templates`       | `k8s/templates.rb`       | ~30   | ERB template loading               |
| `TemplateBinding` | `k8s/renderer.rb`        | ~20   | ERB binding helper                 |
| `Logger`          | `logger.rb`              | 73    | Colored console output             |
| `Constants`       | `constants.rb`           | 60    | Magic numbers                      |
| `Errors`          | `errors.rb`              | 70    | Error class hierarchy              |
| `Retry`           | `deployer/retry.rb`      | ~30   | Retry logic                        |

**Total: ~980 lines across 12 files**

---

## Target Structure

```
lib/nvoi/utils/
├── namer.rb            # ResourceNamer
├── env_resolver.rb     # EnvResolver
├── config_loader.rb    # ConfigLoader + SSHKeyLoader (merge)
├── crypto.rb           # Crypto + Manager (merge)
├── templates.rb        # Templates + TemplateBinding
├── logger.rb           # Logger
├── constants.rb        # Constants
├── errors.rb           # All error classes
└── retry.rb            # Retry logic
```

---

## DRY Opportunities

### 1. Merge ConfigLoader + SSHKeyLoader

Both deal with config initialization. Single file:

```ruby
# utils/config_loader.rb
module Nvoi
  module Utils
    class ConfigLoader
      def load(path)
        # decrypt, parse YAML, load SSH keys, validate
      end
    end
  end
end
```

### 2. Merge Crypto + Manager

`Manager` is just `Crypto` + file I/O. Combine:

```ruby
# utils/crypto.rb
module Nvoi
  module Utils
    class Crypto
      def encrypt(plaintext) ... end
      def decrypt(ciphertext) ... end
    end

    class CredentialStore
      def initialize(crypto) ... end
      def read ... end
      def write(content) ... end
    end
  end
end
```

### 3. Merge Templates + TemplateBinding

Both in k8s/ but are generic ERB utilities:

```ruby
# utils/templates.rb
module Nvoi
  module Utils
    class TemplateRenderer
      def render(name, data) ... end
    end
  end
end
```

### 4. Hostname Builder Duplication

`build_hostname(subdomain, domain)` appears in:

- `steps/tunnel_configurator.rb`
- `service/delete.rb`
- `deployer/service_deployer.rb`

Extract to namer:

```ruby
# utils/namer.rb
def hostname(subdomain, domain)
  subdomain.nil? || subdomain.empty? || subdomain == "@" ? domain : "#{subdomain}.#{domain}"
end
```

---

## Migration Steps

1. Create `lib/nvoi/utils/` directory
2. Move `logger.rb` → `utils/logger.rb` (no changes)
3. Move `constants.rb` → `utils/constants.rb` (no changes)
4. Move `errors.rb` → `utils/errors.rb` (no changes)
5. Merge `config/naming.rb` → `utils/namer.rb` + add `hostname` method
6. Merge `config/env_resolver.rb` → `utils/env_resolver.rb`
7. Merge `config/loader.rb` + `config/ssh_keys.rb` → `utils/config_loader.rb`
8. Merge `credentials/crypto.rb` + `credentials/manager.rb` → `utils/crypto.rb`
9. Merge `k8s/templates.rb` + `k8s/renderer.rb` → `utils/templates.rb`
10. Move `deployer/retry.rb` → `utils/retry.rb`
11. Update all requires

---

## Estimated Effort

- **Lines to consolidate:** ~980
- **Files created:** 9
- **Files deleted:** 12 (all current locations)
- **DRY savings:** ~50 lines (hostname duplication, merged classes)
