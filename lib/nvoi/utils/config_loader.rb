# frozen_string_literal: true

require "tempfile"
require "fileutils"

module Nvoi
  module Utils
    # ConfigLoader handles loading and initializing configuration from encrypted files
    module ConfigLoader
      class << self
        # Load reads and parses the deployment configuration from encrypted file
        def load(config_path, credentials_path: nil, master_key_path: nil)
          working_dir = config_path && !config_path.empty? ? File.dirname(config_path) : "."
          enc_path = credentials_path.nil? || credentials_path.empty? ? config_path : credentials_path

          manager = CredentialStore.new(working_dir, enc_path, master_key_path)
          plaintext = manager.read
          raise Errors::ConfigError, "Failed to decrypt credentials" unless plaintext

          data = YAML.safe_load(plaintext, permitted_classes: [Symbol])
          raise Errors::ConfigError, "Invalid config format" unless data.is_a?(Hash)

          deploy_config = Configuration::Deploy.new(data)
          cfg = Configuration::Root.new(deploy_config)

          load_ssh_keys(cfg)
          cfg.validate_config
          generate_resource_names(cfg)

          cfg
        end

        # Get database credentials from config
        def get_database_credentials(db_config, namer = nil)
          return nil unless db_config

          adapter = db_config.adapter&.downcase
          return nil unless adapter

          provider = External::Database.provider_for(adapter)

          if db_config.url && !db_config.url.empty?
            creds = provider.parse_url(db_config.url)
            host_path = nil

            if provider.is_a?(External::Database::Sqlite) && namer && db_config.servers&.any?
              host_path = resolve_sqlite_host_path(db_config, namer, creds.database || "app.db")
            end

            return Objects::Database::Credentials.new(
              user: creds.user,
              password: creds.password,
              host: creds.host,
              port: creds.port,
              database: creds.database,
              path: creds.path,
              host_path:
            )
          end

          # Fall back to secrets-based credentials
          case adapter
          when "postgres", "postgresql"
            Objects::Database::Credentials.new(
              port: provider.default_port,
              user: db_config.secrets["POSTGRES_USER"],
              password: db_config.secrets["POSTGRES_PASSWORD"],
              database: db_config.secrets["POSTGRES_DB"]
            )
          when "mysql", "mysql2"
            Objects::Database::Credentials.new(
              port: provider.default_port,
              user: db_config.secrets["MYSQL_USER"],
              password: db_config.secrets["MYSQL_PASSWORD"],
              database: db_config.secrets["MYSQL_DATABASE"]
            )
          when "sqlite", "sqlite3"
            Objects::Database::Credentials.new(
              database: "app.db",
              host_path: resolve_sqlite_host_path(db_config, namer, "app.db")
            )
          else
            raise Errors::ConfigError, "Unsupported database adapter: #{adapter}"
          end
        end

        private

          def load_ssh_keys(cfg)
            ssh_keys = cfg.deploy.application.ssh_keys

            unless ssh_keys
              raise Errors::ConfigError, "ssh_keys section is required in config. Run 'nvoi credentials edit' to generate keys."
            end

            raise Errors::ConfigError, "ssh_keys.private_key is required" unless ssh_keys.private_key && !ssh_keys.private_key.empty?
            raise Errors::ConfigError, "ssh_keys.public_key is required" unless ssh_keys.public_key && !ssh_keys.public_key.empty?

            temp_dir = Dir.mktmpdir("nvoi-ssh-")

            private_key_path = File.join(temp_dir, "id_nvoi")
            File.write(private_key_path, ssh_keys.private_key)
            File.chmod(0o600, private_key_path)

            public_key_path = File.join(temp_dir, "id_nvoi.pub")
            File.write(public_key_path, ssh_keys.public_key)
            File.chmod(0o644, public_key_path)

            cfg.ssh_key_path = private_key_path
            cfg.ssh_public_key = ssh_keys.public_key.strip
          end

          def generate_resource_names(cfg)
            namer = cfg.namer
            cfg.container_prefix = namer.infer_container_prefix
            master_group = find_master_server_group(cfg)
            cfg.server_name = namer.server_name(master_group, 1)
            cfg.firewall_name = namer.firewall_name
            cfg.network_name = namer.network_name
            cfg.docker_network_name = namer.docker_network_name
          end

          def find_master_server_group(cfg)
            servers = cfg.deploy.application.servers
            return "master" if servers.empty?

            servers.each { |name, srv_cfg| return name if srv_cfg&.master }
            return servers.keys.first if servers.size == 1

            "master"
          end

          def resolve_sqlite_host_path(db_config, namer, filename = "app.db")
            return nil unless namer && db_config.servers&.any?

            server_name = db_config.servers.first
            mount = db_config.mount

            if mount && !mount.empty?
              vol_name = mount.keys.first
              base_path = namer.server_volume_host_path(server_name, vol_name)
              return "#{base_path}/#{filename}"
            end

            nil
          end
      end

      # Generate a new Ed25519 keypair using ssh-keygen
      def self.generate_keypair
        temp_dir = Dir.mktmpdir("nvoi-keygen-")
        key_path = File.join(temp_dir, "id_nvoi")

        begin
          result = system(
            "ssh-keygen", "-t", "ed25519", "-N", "", "-C", "nvoi-deploy", "-f", key_path,
            out: File::NULL, err: File::NULL
          )

          raise Errors::ConfigError, "Failed to generate SSH keypair (ssh-keygen not available?)" unless result

          private_key = File.read(key_path)
          public_key = File.read("#{key_path}.pub").strip

          [private_key, public_key]
        ensure
          FileUtils.rm_rf(temp_dir)
        end
      end
    end
  end
end
