# frozen_string_literal: true


module Nvoi
  module Configuration
    # Builder for constructing and modifying config data hashes
    # Replaces ConfigApi with a cleaner, chainable interface
    class Builder
      COMPUTE_PROVIDERS = %w[hetzner aws scaleway].freeze
      DOMAIN_PROVIDERS = %w[cloudflare].freeze
      DATABASE_ADAPTERS = %w[postgres postgresql mysql sqlite sqlite3].freeze

      attr_reader :data

      def initialize(data = nil)
        @data = data || { "application" => {} }
      end

      # ─── Class Methods ───

      def self.from_hash(data)
        new(data)
      end

      def self.init(name:, environment: "production")
        raise ArgumentError, "name is required" if name.nil? || name.to_s.empty?

        master_key = Utils::Crypto.generate_key
        private_key, public_key = Utils::ConfigLoader.generate_keypair

        builder = new
        builder.name(name)
        builder.environment(environment)
        builder.ssh_keys(private_key, public_key)

        yaml = YAML.dump(builder.to_h)
        encrypted_config = Utils::Crypto.encrypt(yaml, master_key)

        Result::Init.new(
          config: encrypted_config,
          master_key:,
          ssh_public_key: public_key
        )
      rescue ArgumentError => e
        Result::Init.new(error_type: :invalid_args, error_message: e.message)
      rescue Errors::ConfigError => e
        Result::Init.new(error_type: :config_error, error_message: e.message)
      end

      # ─── Basic Setters ───

      def name(n)
        app["name"] = n.to_s
        self
      end

      def environment(e)
        app["environment"] = e.to_s
        self
      end

      def ssh_keys(private_key, public_key)
        app["ssh_keys"] = {
          "private_key" => private_key,
          "public_key" => public_key
        }
        self
      end

      # ─── Compute Provider ───

      def compute_provider(provider, **opts)
        validate_presence!(provider, "provider")
        validate_inclusion!(provider.to_s, COMPUTE_PROVIDERS, "provider")

        app["compute_provider"] = { provider.to_s => build_compute_config(provider.to_s, opts) }
        wrap_success
      end

      def remove_compute_provider
        app["compute_provider"] = {}
        wrap_success
      end

      # ─── Domain Provider ───

      def domain_provider(provider, **opts)
        validate_presence!(provider, "provider")
        validate_inclusion!(provider.to_s, DOMAIN_PROVIDERS, "provider")

        app["domain_provider"] = { provider.to_s => build_domain_config(provider.to_s, opts) }
        wrap_success
      end

      def remove_domain_provider
        app["domain_provider"] = {}
        wrap_success
      end

      # ─── Server ───

      def server(name, master: false, type: nil, location: nil, count: 1)
        validate_presence!(name, "name")
        validate_positive!(count, "count") if count

        servers[name.to_s] = {
          "master" => master,
          "type" => type,
          "location" => location,
          "count" => count
        }.compact
        wrap_success
      end

      def remove_server(name)
        validate_presence!(name, "name")
        validate_exists!(servers, name.to_s, "server")
        check_server_references(name.to_s)

        servers.delete(name.to_s)
        wrap_success
      end

      # ─── Volume ───

      def volume(server_name, name, size: 10)
        validate_presence!(server_name, "server")
        validate_presence!(name, "name")
        validate_positive!(size, "size") if size
        validate_exists!(servers, server_name.to_s, "server")

        servers[server_name.to_s]["volumes"] ||= {}
        servers[server_name.to_s]["volumes"][name.to_s] = { "size" => size }
        wrap_success
      end

      def remove_volume(server_name, name)
        validate_presence!(server_name, "server")
        validate_presence!(name, "name")
        validate_exists!(servers, server_name.to_s, "server")

        volumes = servers[server_name.to_s]["volumes"] || {}
        validate_exists!(volumes, name.to_s, "volume")

        volumes.delete(name.to_s)
        wrap_success
      end

      # ─── App ───

      def app_entry(name, servers:, domain: nil, subdomain: nil, port: nil, command: nil, pre_run_command: nil, env: nil, mounts: nil)
        validate_presence!(name, "name")
        validate_servers_array!(servers)
        validate_server_refs!(servers)

        apps[name.to_s] = {
          "servers" => servers.map(&:to_s),
          "domain" => domain,
          "subdomain" => subdomain,
          "port" => port,
          "command" => command,
          "pre_run_command" => pre_run_command,
          "env" => env,
          "mounts" => mounts
        }.compact
        wrap_success
      end

      def remove_app(name)
        validate_presence!(name, "name")
        validate_exists!(apps, name.to_s, "app")

        apps.delete(name.to_s)
        wrap_success
      end

      # ─── Database ───

      def database(servers:, adapter:, image: nil, url: nil, user: nil, password: nil, database_name: nil, mount: nil, path: nil)
        validate_servers_array!(servers)
        validate_presence!(adapter, "adapter")
        validate_inclusion!(adapter.to_s.downcase, DATABASE_ADAPTERS, "adapter")
        validate_server_refs!(servers)

        secrets = build_database_secrets(adapter, user, password, database_name)

        app["database"] = {
          "servers" => servers.map(&:to_s),
          "adapter" => adapter.to_s,
          "image" => image,
          "url" => url,
          "secrets" => secrets.empty? ? nil : secrets,
          "mount" => mount,
          "path" => path
        }.compact
        wrap_success
      end

      def remove_database
        app.delete("database")
        wrap_success
      end

      # ─── Service ───

      def service(name, servers:, image:, port: nil, command: nil, env: nil, mount: nil)
        validate_presence!(name, "name")
        validate_servers_array!(servers)
        validate_presence!(image, "image")
        validate_server_refs!(servers)

        services[name.to_s] = {
          "servers" => servers.map(&:to_s),
          "image" => image.to_s,
          "port" => port,
          "command" => command,
          "env" => env,
          "mount" => mount
        }.compact
        wrap_success
      end

      def remove_service(name)
        validate_presence!(name, "name")
        validate_exists!(services, name.to_s, "service")

        services.delete(name.to_s)
        wrap_success
      end

      # ─── Secret ───

      def secret(key, value)
        validate_presence!(key, "key")
        raise ArgumentError, "value is required" if value.nil?

        secrets[key.to_s] = value.to_s
        wrap_success
      end

      def remove_secret(key)
        validate_presence!(key, "key")
        validate_exists!(secrets, key.to_s, "secret")

        secrets.delete(key.to_s)
        wrap_success
      end

      # ─── Env ───

      def env(key, value)
        validate_presence!(key, "key")
        raise ArgumentError, "value is required" if value.nil?

        env_vars[key.to_s] = value.to_s
        wrap_success
      end

      def remove_env(key)
        validate_presence!(key, "key")
        validate_exists!(env_vars, key.to_s, "env")

        env_vars.delete(key.to_s)
        wrap_success
      end

      # ─── Output ───

      def to_h
        @data
      end

      def to_yaml
        YAML.dump(@data)
      end

      private

        def app
          @data["application"] ||= {}
        end

        def servers
          app["servers"] ||= {}
        end

        def apps
          app["app"] ||= {}
        end

        def services
          app["services"] ||= {}
        end

        def secrets
          app["secrets"] ||= {}
        end

        def env_vars
          app["env"] ||= {}
        end

        # ─── Validation Helpers ───

        def validate_presence!(value, field)
          raise ArgumentError, "#{field} is required" if value.nil? || value.to_s.empty?
        end

        def validate_inclusion!(value, list, field)
          raise ArgumentError, "#{field} must be one of: #{list.join(', ')}" unless list.include?(value)
        end

        def validate_positive!(value, field)
          raise ArgumentError, "#{field} must be positive" if value && value < 1
        end

        def validate_exists!(hash, key, type)
          raise Errors::ConfigValidationError, "#{type} '#{key}' not found" unless hash.key?(key)
        end

        def validate_servers_array!(server_refs)
          raise ArgumentError, "servers is required" if server_refs.nil? || server_refs.empty?
          raise ArgumentError, "servers must be an array" unless server_refs.is_a?(Array)
        end

        def validate_server_refs!(server_refs)
          defined = servers.keys
          server_refs.each do |ref|
            raise Errors::ConfigValidationError, "server '#{ref}' not found" unless defined.include?(ref.to_s)
          end
        end

        def check_server_references(server_name)
          apps.each do |app_name, cfg|
            if (cfg["servers"] || []).include?(server_name)
              raise Errors::ConfigValidationError, "app.#{app_name} references server '#{server_name}'"
            end
          end

          db = app["database"]
          if db && (db["servers"] || []).include?(server_name)
            raise Errors::ConfigValidationError, "database references server '#{server_name}'"
          end

          services.each do |svc_name, cfg|
            if (cfg["servers"] || []).include?(server_name)
              raise Errors::ConfigValidationError, "services.#{svc_name} references server '#{server_name}'"
            end
          end
        end

        # ─── Config Builders ───

        def build_compute_config(provider, opts)
          case provider
          when "hetzner"
            {
              "api_token" => opts[:api_token],
              "server_type" => opts[:server_type],
              "server_location" => opts[:server_location]
            }.compact
          when "aws"
            {
              "access_key_id" => opts[:access_key_id],
              "secret_access_key" => opts[:secret_access_key],
              "region" => opts[:region],
              "instance_type" => opts[:instance_type]
            }.compact
          when "scaleway"
            {
              "secret_key" => opts[:secret_key],
              "project_id" => opts[:project_id],
              "zone" => opts[:zone],
              "server_type" => opts[:server_type]
            }.compact
          end
        end

        def build_domain_config(provider, opts)
          case provider
          when "cloudflare"
            {
              "api_token" => opts[:api_token],
              "account_id" => opts[:account_id]
            }.compact
          end
        end

        def build_database_secrets(adapter, user, password, database_name)
          case adapter.to_s.downcase
          when "postgres", "postgresql"
            {
              "POSTGRES_USER" => user,
              "POSTGRES_PASSWORD" => password,
              "POSTGRES_DB" => database_name
            }.compact
          when "mysql"
            {
              "MYSQL_USER" => user,
              "MYSQL_PASSWORD" => password,
              "MYSQL_DATABASE" => database_name
            }.compact
          else
            {}
          end
        end

        def wrap_success
          Result.success(@data)
        end

        def wrap_failure(type, message)
          Result.failure(type, message)
        end
    end
  end
end
