# frozen_string_literal: true

module Nvoi
  class Cli
    module Config
      # Command helper for all config operations
      # Uses CredentialStore for crypto, Configuration::Builder for transformations
      class Command
        def initialize(options)
          @options = options
          @working_dir = options[:dir] || "."
        end

        # Initialize new config
        def init(name, environment)
          result = Configuration::Builder.init(name:, environment:)

          if result.failure?
            error("Failed to initialize: #{result.error_message}")
            return
          end

          # Write encrypted config
          config_path = File.join(@working_dir, Utils::DEFAULT_ENCRYPTED_FILE)
          key_path = File.join(@working_dir, Utils::DEFAULT_KEY_FILE)

          File.binwrite(config_path, result.config)
          File.write(key_path, "#{result.master_key}\n", perm: 0o600)

          update_gitignore

          success("Created #{Utils::DEFAULT_ENCRYPTED_FILE}")
          success("Created #{Utils::DEFAULT_KEY_FILE} (keep safe, never commit)")
          puts
          puts "Next steps:"
          puts "  nvoi config domain set cloudflare --api-token=TOKEN --account-id=ID"
          puts "  nvoi config provider set hetzner --api-token=TOKEN --server-type=cx22 --location=fsn1"
          puts "  nvoi config server set web --master"
        end

        # Domain provider
        def domain_set(provider, api_token:, account_id:)
          with_config do |builder|
            builder.domain_provider(provider, api_token:, account_id:)
          end
        end

        def domain_rm
          with_config do |builder|
            builder.remove_domain_provider
          end
        end

        # Compute provider
        def provider_set(provider, **opts)
          with_config do |builder|
            builder.compute_provider(provider, **opts)
          end
        end

        def provider_rm
          with_config do |builder|
            builder.remove_compute_provider
          end
        end

        # Server
        def server_set(name, master: false, type: nil, location: nil, count: 1)
          with_config do |builder|
            builder.server(name, master:, type:, location:, count:)
          end
        end

        def server_rm(name)
          with_config do |builder|
            builder.remove_server(name)
          end
        end

        # Volume
        def volume_set(server, name, size: 10)
          with_config do |builder|
            builder.volume(server, name, size:)
          end
        end

        def volume_rm(server, name)
          with_config do |builder|
            builder.remove_volume(server, name)
          end
        end

        # App
        def app_set(name, servers:, **opts)
          with_config do |builder|
            builder.app_entry(name, servers:, **opts)
          end
        end

        def app_rm(name)
          with_config do |builder|
            builder.remove_app(name)
          end
        end

        # Database
        def database_set(servers:, adapter:, **opts)
          with_config do |builder|
            builder.database(servers:, adapter:, **opts)
          end
        end

        def database_rm
          with_config do |builder|
            builder.remove_database
          end
        end

        # Service
        def service_set(name, servers:, image:, **opts)
          with_config do |builder|
            builder.service(name, servers:, image:, **opts)
          end
        end

        def service_rm(name)
          with_config do |builder|
            builder.remove_service(name)
          end
        end

        # Secret
        def secret_set(key_name, value)
          with_config do |builder|
            builder.secret(key_name, value)
          end
        end

        def secret_rm(key_name)
          with_config do |builder|
            builder.remove_secret(key_name)
          end
        end

        # Env
        def env_set(key_name, value)
          with_config do |builder|
            builder.env(key_name, value)
          end
        end

        def env_rm(key_name)
          with_config do |builder|
            builder.remove_env(key_name)
          end
        end

        private

          def with_config
            store = Utils::CredentialStore.new(
              @working_dir,
              @options[:credentials],
              @options[:master_key]
            )

            unless store.exists?
              error("Config not found: #{store.encrypted_path}")
              error("Run 'nvoi config init --name=myapp' first")
              return
            end

            # Read and parse
            yaml = store.read
            data = YAML.safe_load(yaml, permitted_classes: [Symbol])

            # Transform using Builder
            builder = Configuration::Builder.from_hash(data)
            result = yield(builder)

            if result.failure?
              error("#{result.error_type}: #{result.error_message}")
            else
              # Serialize and write
              store.write(builder.to_yaml)
              success("Config updated")
            end
          rescue Errors::CredentialError => e
            error(e.message)
          rescue Errors::DecryptionError => e
            error("Decryption failed: #{e.message}")
          rescue ArgumentError => e
            error("invalid_args: #{e.message}")
          rescue Errors::ConfigValidationError => e
            error("validation_error: #{e.message}")
          end

          def update_gitignore
            gitignore_path = File.join(@working_dir, ".gitignore")
            entries = ["deploy.key", ".env", ".env.*", "!.env.example", "!.env.*.example"]

            existing = File.exist?(gitignore_path) ? File.read(gitignore_path) : ""
            additions = entries.reject { |e| existing.include?(e) }

            return if additions.empty?

            File.open(gitignore_path, "a") do |f|
              f.puts "" unless existing.end_with?("\n") || existing.empty?
              f.puts "# NVOI - sensitive files"
              additions.each { |e| f.puts e }
            end
          end

          def success(msg)
            puts "\e[32m✓\e[0m #{msg}"
          end

          def error(msg)
            warn "\e[31m✗\e[0m #{msg}"
          end
      end
    end
  end
end
