# frozen_string_literal: true

module Nvoi
  module Configuration
    # Root holds the complete configuration including deployment config and runtime settings
    class Root
      attr_accessor :deploy, :ssh_key_path, :ssh_public_key, :server_name,
                    :firewall_name, :network_name, :docker_network_name, :container_prefix, :namer

      def initialize(deploy_config)
        @deploy = deploy_config
        @namer = nil
      end

      def namer
        @namer ||= Utils::Namer.new(self)
      end

      def env_for_service(service_name)
        Utils::EnvResolver.new(self).env_for_service(service_name)
      end

      def validate_config
        app = @deploy.application
        validate_providers_config
        validate_database_secrets(app.database) if app.database
        inject_database_env_vars
        validate_service_server_bindings
        validate_domain_uniqueness
      end

      def provider_name
        return "hetzner" if @deploy.application.compute_provider.hetzner
        return "aws" if @deploy.application.compute_provider.aws
        return "scaleway" if @deploy.application.compute_provider.scaleway

        ""
      end

      def hetzner
        @deploy.application.compute_provider.hetzner
      end

      def aws
        @deploy.application.compute_provider.aws
      end

      def scaleway
        @deploy.application.compute_provider.scaleway
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
          defined_servers = {}
          master_count = 0

          app.servers.each do |server_name, server_config|
            defined_servers[server_name] = true
            master_count += 1 if server_config&.master
          end

          if app.servers.empty?
            has_services = !app.app.empty? || app.database || !app.services.empty?
            raise Errors::ConfigValidationError, "servers must be defined when deploying services" if has_services
          end

          if app.servers.size > 1
            raise Errors::ConfigValidationError, "when multiple servers are defined, exactly one must have master: true" if master_count.zero?
            raise Errors::ConfigValidationError, "only one server can have master: true, found #{master_count}" if master_count > 1
          elsif app.servers.size == 1 && master_count > 1
            raise Errors::ConfigValidationError, "only one server can have master: true, found #{master_count}"
          end

          app.app.each do |svc_name, svc_config|
            raise Errors::ConfigValidationError, "app.#{svc_name}: servers field is required" if svc_config.servers.empty?

            svc_config.servers.each do |server_ref|
              raise Errors::ConfigValidationError, "app.#{svc_name}: references undefined server '#{server_ref}'" unless defined_servers[server_ref]
            end
          end

          if app.database
            raise Errors::ConfigValidationError, "database: servers field is required" if app.database.servers.empty?

            app.database.servers.each do |server_ref|
              raise Errors::ConfigValidationError, "database: references undefined server '#{server_ref}'" unless defined_servers[server_ref]
            end
          end

          app.services.each do |svc_name, svc_config|
            raise Errors::ConfigValidationError, "services.#{svc_name}: servers field is required" if svc_config.servers.empty?

            svc_config.servers.each do |server_ref|
              raise Errors::ConfigValidationError, "services.#{svc_name}: references undefined server '#{server_ref}'" unless defined_servers[server_ref]
            end
          end
        end

        def validate_database_secrets(db)
          adapter = db.adapter&.downcase
          return if db.url && !db.url.empty?

          case adapter
          when "postgres", "postgresql"
            %w[POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB].each do |key|
              raise Errors::ConfigValidationError, "postgres database requires #{key} in secrets (or provide database.url)" unless db.secrets[key]
            end
          when "mysql"
            %w[MYSQL_USER MYSQL_PASSWORD MYSQL_DATABASE].each do |key|
              raise Errors::ConfigValidationError, "mysql database requires #{key} in secrets (or provide database.url)" unless db.secrets[key]
            end
          when "sqlite", "sqlite3"
            # SQLite doesn't require secrets
          end
        end

        def validate_providers_config
          app = @deploy.application

          unless app.domain_provider.cloudflare
            raise Errors::ConfigValidationError, "domain provider required: currently only cloudflare is supported"
          end

          cf = app.domain_provider.cloudflare
          raise Errors::ConfigValidationError, "cloudflare api_token is required" if cf.api_token.nil? || cf.api_token.empty?
          raise Errors::ConfigValidationError, "cloudflare account_id is required" if cf.account_id.nil? || cf.account_id.empty?

          has_provider = false

          if app.compute_provider.hetzner
            has_provider = true
            h = app.compute_provider.hetzner
            raise Errors::ConfigValidationError, "hetzner api_token is required" if h.api_token.nil? || h.api_token.empty?
            raise Errors::ConfigValidationError, "hetzner server_type is required" if h.server_type.nil? || h.server_type.empty?
            raise Errors::ConfigValidationError, "hetzner server_location is required" if h.server_location.nil? || h.server_location.empty?
          end

          if app.compute_provider.aws
            has_provider = true
            a = app.compute_provider.aws
            raise Errors::ConfigValidationError, "aws access_key_id is required" if a.access_key_id.nil? || a.access_key_id.empty?
            raise Errors::ConfigValidationError, "aws secret_access_key is required" if a.secret_access_key.nil? || a.secret_access_key.empty?
            raise Errors::ConfigValidationError, "aws region is required" if a.region.nil? || a.region.empty?
            raise Errors::ConfigValidationError, "aws instance_type is required" if a.instance_type.nil? || a.instance_type.empty?
          end

          if app.compute_provider.scaleway
            has_provider = true
            s = app.compute_provider.scaleway
            raise Errors::ConfigValidationError, "scaleway secret_key is required" if s.secret_key.nil? || s.secret_key.empty?
            raise Errors::ConfigValidationError, "scaleway project_id is required" if s.project_id.nil? || s.project_id.empty?
            raise Errors::ConfigValidationError, "scaleway server_type is required" if s.server_type.nil? || s.server_type.empty?
          end

          raise Errors::ConfigValidationError, "compute provider required: hetzner, aws, or scaleway must be configured" unless has_provider
        end

        def inject_database_env_vars
          app = @deploy.application
          return unless app.database

          db = app.database
          adapter = db.adapter&.downcase
          return unless adapter

          provider = External::Database.provider_for(adapter)
          return unless provider.needs_container?

          creds = parse_database_credentials(db, provider)
          return unless creds

          db_host = namer.database_service_name
          env_vars = provider.app_env(creds, host: db_host)

          app.app.each_value do |svc_config|
            svc_config.env ||= {}
            env_vars.each { |key, value| svc_config.env[key] ||= value }
          end
        end

        def parse_database_credentials(db, provider)
          return provider.parse_url(db.url) if db.url && !db.url.empty?

          adapter = db.adapter&.downcase
          case adapter
          when "postgres", "postgresql"
            External::Database::Credentials.new(
              user: db.secrets["POSTGRES_USER"],
              password: db.secrets["POSTGRES_PASSWORD"],
              database: db.secrets["POSTGRES_DB"],
              port: provider.default_port
            )
          when "mysql"
            External::Database::Credentials.new(
              user: db.secrets["MYSQL_USER"],
              password: db.secrets["MYSQL_PASSWORD"],
              database: db.secrets["MYSQL_DATABASE"],
              port: provider.default_port
            )
          end
        end

        def validate_domain_uniqueness
          app = @deploy.application
          return unless app.app

          seen = {}
          app.app.each do |name, cfg|
            next unless cfg.domain && !cfg.domain.empty?

            hostnames = Utils::Namer.build_hostnames(cfg.subdomain, cfg.domain)
            hostnames.each do |hostname|
              if seen[hostname]
                raise Errors::ConfigValidationError,
                  "domain '#{hostname}' used by both '#{seen[hostname]}' and '#{name}'"
              end
              seen[hostname] = name
            end
          end
        end
    end
  end
end
