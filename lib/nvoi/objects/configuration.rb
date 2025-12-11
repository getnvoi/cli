# frozen_string_literal: true

module Nvoi
  module Objects
    # Configuration module contains all configuration-related classes
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
              Database::Credentials.new(
                user: db.secrets["POSTGRES_USER"],
                password: db.secrets["POSTGRES_PASSWORD"],
                database: db.secrets["POSTGRES_DB"],
                port: provider.default_port
              )
            when "mysql"
              Database::Credentials.new(
                user: db.secrets["MYSQL_USER"],
                password: db.secrets["MYSQL_PASSWORD"],
                database: db.secrets["MYSQL_DATABASE"],
                port: provider.default_port
              )
            end
          end
      end

      # Deploy represents the root deployment configuration
      class Deploy
        attr_accessor :application

        def initialize(data = {})
          @application = Application.new(data["application"] || {})
        end
      end

      # Application contains application-level configuration
      class Application
        attr_accessor :name, :environment, :domain_provider, :compute_provider,
                      :keep_count, :servers, :app, :database, :services, :env,
                      :secrets, :ssh_keys

        def initialize(data = {})
          @name = data["name"]
          @environment = data["environment"] || "production"
          @domain_provider = DomainProvider.new(data["domain_provider"] || {})
          @compute_provider = ComputeProvider.new(data["compute_provider"] || {})
          @keep_count = data["keep_count"]&.to_i
          @servers = (data["servers"] || {}).transform_values { |v| Server.new(v || {}) }
          @app = (data["app"] || {}).transform_values { |v| AppService.new(v || {}) }
          @database = data["database"] ? DatabaseCfg.new(data["database"]) : nil
          @services = (data["services"] || {}).transform_values { |v| Service.new(v || {}) }
          @env = data["env"] || {}
          @secrets = data["secrets"] || {}
          @ssh_keys = data["ssh_keys"] ? SshKey.new(data["ssh_keys"]) : nil
        end
      end

      # DomainProvider contains domain provider configuration
      class DomainProvider
        attr_accessor :cloudflare

        def initialize(data = {})
          @cloudflare = data["cloudflare"] ? Cloudflare.new(data["cloudflare"]) : nil
        end
      end

      # ComputeProvider contains compute provider configuration
      class ComputeProvider
        attr_accessor :hetzner, :aws, :scaleway

        def initialize(data = {})
          @hetzner = data["hetzner"] ? Hetzner.new(data["hetzner"]) : nil
          @aws = data["aws"] ? AwsCfg.new(data["aws"]) : nil
          @scaleway = data["scaleway"] ? Scaleway.new(data["scaleway"]) : nil
        end
      end

      # Cloudflare contains Cloudflare-specific configuration
      class Cloudflare
        attr_accessor :api_token, :account_id

        def initialize(data = {})
          @api_token = data["api_token"]
          @account_id = data["account_id"]
        end
      end

      # Hetzner contains Hetzner-specific configuration
      class Hetzner
        attr_accessor :api_token, :server_type, :server_location

        def initialize(data = {})
          @api_token = data["api_token"]
          @server_type = data["server_type"]
          @server_location = data["server_location"]
        end
      end

      # AwsCfg contains AWS-specific configuration
      class AwsCfg
        attr_accessor :access_key_id, :secret_access_key, :region, :instance_type

        def initialize(data = {})
          @access_key_id = data["access_key_id"]
          @secret_access_key = data["secret_access_key"]
          @region = data["region"]
          @instance_type = data["instance_type"]
        end
      end

      # Scaleway contains Scaleway-specific configuration
      class Scaleway
        attr_accessor :secret_key, :project_id, :zone, :server_type

        def initialize(data = {})
          @secret_key = data["secret_key"]
          @project_id = data["project_id"]
          @zone = data["zone"] || "fr-par-1"
          @server_type = data["server_type"]
        end
      end

      # ServerVolume defines a volume attached to a server
      class ServerVolume
        attr_accessor :size

        def initialize(data = {})
          raise ArgumentError, "volume config must be a hash with 'size' key" unless data.is_a?(Hash)

          @size = data["size"]&.to_i || 10
        end
      end

      # Server contains server instance configuration
      class Server
        attr_accessor :master, :type, :location, :count, :volumes

        def initialize(data = {})
          @master = data["master"] || false
          @type = data["type"]
          @location = data["location"]
          @count = data["count"]&.to_i || 1
          @volumes = (data["volumes"] || {}).transform_values { |v| ServerVolume.new(v || {}) }
        end
      end

      # AppService defines a service in the app section
      class AppService
        attr_accessor :servers, :domain, :subdomain, :port, :healthcheck,
                      :command, :pre_run_command, :env, :mounts

        def initialize(data = {})
          @servers = data["servers"] || []
          @domain = data["domain"]
          @subdomain = data["subdomain"]
          @port = data["port"]&.to_i
          @healthcheck = data["healthcheck"] ? HealthCheck.new(data["healthcheck"]) : nil
          @command = data["command"]
          @pre_run_command = data["pre_run_command"]
          @env = data["env"] || {}
          @mounts = data["mounts"] || {}
        end
      end

      # HealthCheck defines health check configuration
      class HealthCheck
        attr_accessor :type, :path, :port, :command, :interval, :timeout, :retries

        def initialize(data = {})
          @type = data["type"]
          @path = data["path"]
          @port = data["port"]&.to_i
          @command = data["command"]
          @interval = data["interval"]
          @timeout = data["timeout"]
          @retries = data["retries"]&.to_i
        end
      end

      # DatabaseCfg defines database configuration
      class DatabaseCfg
        attr_accessor :servers, :adapter, :url, :image, :mount, :secrets, :path

        def initialize(data = {})
          @servers = data["servers"] || []
          @adapter = data["adapter"]
          @url = data["url"]
          @image = data["image"]
          @mount = data["mount"] || {}
          @secrets = data["secrets"] || {}
          @path = data["path"]
        end

        def to_service_spec(namer)
          return nil if @adapter&.downcase&.start_with?("sqlite")

          port = case @adapter&.downcase
          when "mysql" then 3306
          else 5432
          end

          image = @image || Utils::Constants::DATABASE_IMAGES[@adapter&.downcase]

          ServiceSpec.new(
            name: namer.database_service_name,
            image:,
            port:,
            env: nil,
            mounts: @mount,
            replicas: 1,
            stateful_set: true,
            secrets: @secrets,
            servers: @servers
          )
        end
      end

      # Service defines a generic service
      class Service
        attr_accessor :servers, :image, :port, :command, :env, :mount

        def initialize(data = {})
          @servers = data["servers"] || []
          @image = data["image"]
          @port = data["port"]&.to_i
          @command = data["command"]
          @env = data["env"] || {}
          @mount = data["mount"] || {}
        end

        def to_service_spec(app_name, service_name)
          cmd = @command ? @command.split : []
          port = @port && @port.positive? ? @port : infer_port_from_image

          ServiceSpec.new(
            name: "#{app_name}-#{service_name}",
            image: @image,
            port:,
            command: cmd,
            env: @env,
            mounts: @mount,
            replicas: 1,
            stateful_set: false,
            servers: @servers
          )
        end

        private

          def infer_port_from_image
            case @image
            when /redis/ then 6379
            when /postgres/ then 5432
            when /mysql/ then 3306
            when /memcache/ then 11211
            when /mongo/ then 27017
            when /elastic/ then 9200
            else 0
            end
          end
      end

      # SshKey defines SSH key content (stored in encrypted config)
      class SshKey
        attr_accessor :private_key, :public_key

        def initialize(data = {})
          @private_key = data["private_key"]
          @public_key = data["public_key"]
        end
      end
    end
  end
end
