# frozen_string_literal: true

module Nvoi
  module Config
    # Configuration holds the complete configuration including deployment config and runtime settings
    class Configuration
      attr_accessor :deploy, :ssh_key_path, :ssh_public_key, :server_name,
                    :firewall_name, :network_name, :docker_network_name, :container_prefix

      def initialize(deploy_config)
        @deploy = deploy_config
        @namer = nil
      end

      # Returns the ResourceNamer for centralized naming
      def namer
        @namer ||= ResourceNamer.new(self)
      end

      # Returns environment variables for a specific service
      def env_for_service(service_name)
        resolver = EnvResolver.new(self)
        resolver.env_for_service(service_name)
      end

      # Validate config structure
      def validate_config
        app = @deploy.application

        # Validate provider configuration
        validate_providers_config

        # Validate database secrets (if database configured)
        validate_database_secrets(app.database) if app.database

        # Auto-inject database environment variables into app services
        inject_database_env_vars

        # Validate service-to-server bindings
        validate_service_server_bindings
      end

      # ProviderName returns the name of the configured compute provider
      def provider_name
        return "hetzner" if @deploy.application.compute_provider.hetzner
        return "aws" if @deploy.application.compute_provider.aws

        ""
      end

      def hetzner
        @deploy.application.compute_provider.hetzner
      end

      def aws
        @deploy.application.compute_provider.aws
      end

      def cloudflare
        @deploy.application.domain_provider.cloudflare
      end

      def keep_count_value
        count = @deploy.application.keep_count
        count && count.positive? ? count : 2
      end

      private

        def validate_service_server_bindings
          app = @deploy.application

          # Collect all defined server names and validate single master
          defined_servers = {}
          master_count = 0

          app.servers.each do |server_name, server_config|
            defined_servers[server_name] = true
            master_count += 1 if server_config&.master
          end

          # Require servers to be defined if any services exist
          if app.servers.empty?
            has_services = !app.app.empty? || app.database || !app.services.empty?
            raise ConfigValidationError, "servers must be defined when deploying services" if has_services
          end

          # Validate master designation
          if app.servers.size > 1
            raise ConfigValidationError, "when multiple servers are defined, exactly one must have master: true" if master_count.zero?
            raise ConfigValidationError, "only one server can have master: true, found #{master_count}" if master_count > 1
          elsif app.servers.size == 1 && master_count > 1
            raise ConfigValidationError, "only one server can have master: true, found #{master_count}"
          end

          # Validate app services
          app.app.each do |service_name, service_config|
            raise ConfigValidationError, "app.#{service_name}: servers field is required" if service_config.servers.empty?

            service_config.servers.each do |server_ref|
              unless defined_servers[server_ref]
                raise ConfigValidationError, "app.#{service_name}: references undefined server '#{server_ref}'"
              end
            end
          end

          # Validate database
          if app.database
            raise ConfigValidationError, "database: servers field is required" if app.database.servers.empty?

            app.database.servers.each do |server_ref|
              raise ConfigValidationError, "database: references undefined server '#{server_ref}'" unless defined_servers[server_ref]
            end
          end

          # Validate additional services
          app.services.each do |service_name, service_config|
            raise ConfigValidationError, "services.#{service_name}: servers field is required" if service_config.servers.empty?

            service_config.servers.each do |server_ref|
              unless defined_servers[server_ref]
                raise ConfigValidationError, "services.#{service_name}: references undefined server '#{server_ref}'"
              end
            end
          end
        end

        def validate_database_secrets(db)
          adapter = db.adapter&.downcase

          case adapter
          when "postgres", "postgresql"
            required_keys = %w[POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB]
            required_keys.each do |key|
              raise ConfigValidationError, "postgres database requires #{key} in secrets" unless db.secrets[key]
            end
          when "mysql"
            required_keys = %w[MYSQL_USER MYSQL_PASSWORD MYSQL_DATABASE]
            required_keys.each do |key|
              raise ConfigValidationError, "mysql database requires #{key} in secrets" unless db.secrets[key]
            end
          when "sqlite3"
            # SQLite doesn't require secrets
          end
        end

        def validate_providers_config
          app = @deploy.application

          # Validate domain provider (required)
          unless app.domain_provider.cloudflare
            raise ConfigValidationError, "domain provider required: currently only cloudflare is supported"
          end

          cf = app.domain_provider.cloudflare
          raise ConfigValidationError, "cloudflare api_token is required" if cf.api_token.nil? || cf.api_token.empty?
          raise ConfigValidationError, "cloudflare account_id is required" if cf.account_id.nil? || cf.account_id.empty?

          # Validate compute provider (at least one required)
          has_provider = false

          if app.compute_provider.hetzner
            has_provider = true
            h = app.compute_provider.hetzner
            raise ConfigValidationError, "hetzner api_token is required" if h.api_token.nil? || h.api_token.empty?
            raise ConfigValidationError, "hetzner server_type is required" if h.server_type.nil? || h.server_type.empty?
            raise ConfigValidationError, "hetzner server_location is required" if h.server_location.nil? || h.server_location.empty?
          end

          if app.compute_provider.aws
            has_provider = true
            a = app.compute_provider.aws
            raise ConfigValidationError, "aws access_key_id is required" if a.access_key_id.nil? || a.access_key_id.empty?
            raise ConfigValidationError, "aws secret_access_key is required" if a.secret_access_key.nil? || a.secret_access_key.empty?
            raise ConfigValidationError, "aws region is required" if a.region.nil? || a.region.empty?
            raise ConfigValidationError, "aws instance_type is required" if a.instance_type.nil? || a.instance_type.empty?
          end

          raise ConfigValidationError, "compute provider required: hetzner or aws must be configured" unless has_provider
        end

        def inject_database_env_vars
          app = @deploy.application

          # Skip if no database configured
          return unless app.database

          db = app.database
          adapter = db.adapter&.downcase

          # SQLite doesn't need network connection vars
          return if adapter == "sqlite3"

          # Build connection variables
          db_host = namer.database_service_name
          db_port, db_user, db_password, db_name = extract_db_credentials(adapter, db)

          return unless db_user && db_password && db_name

          # Build DATABASE_URL
          database_url = case adapter
          when "postgres", "postgresql"
            "postgresql://#{db_user}:#{db_password}@#{db_host}:#{db_port}/#{db_name}"
          when "mysql"
            "mysql://#{db_user}:#{db_password}@#{db_host}:#{db_port}/#{db_name}"
          end

          # Inject into all app services
          app.app.each_value do |service_config|
            service_config.env ||= {}

            # Only inject if not already set by user
            service_config.env["DATABASE_URL"] ||= database_url

            case adapter
            when "postgres", "postgresql"
              unless service_config.env.key?("POSTGRES_HOST")
                service_config.env["POSTGRES_HOST"] = db_host
                service_config.env["POSTGRES_PORT"] = db_port
                service_config.env["POSTGRES_USER"] = db_user
                service_config.env["POSTGRES_PASSWORD"] = db_password
                service_config.env["POSTGRES_DB"] = db_name
              end
            when "mysql"
              unless service_config.env.key?("MYSQL_HOST")
                service_config.env["MYSQL_HOST"] = db_host
                service_config.env["MYSQL_PORT"] = db_port
                service_config.env["MYSQL_USER"] = db_user
                service_config.env["MYSQL_PASSWORD"] = db_password
                service_config.env["MYSQL_DATABASE"] = db_name
              end
            end
          end
        end

        def extract_db_credentials(adapter, db)
          case adapter
          when "postgres", "postgresql"
            ["5432", db.secrets["POSTGRES_USER"], db.secrets["POSTGRES_PASSWORD"], db.secrets["POSTGRES_DB"]]
          when "mysql"
            ["3306", db.secrets["MYSQL_USER"], db.secrets["MYSQL_PASSWORD"], db.secrets["MYSQL_DATABASE"]]
          else
            [nil, nil, nil, nil]
          end
        end
    end
  end
end
