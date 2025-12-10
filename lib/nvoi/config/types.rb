# frozen_string_literal: true

module Nvoi
  module Config
    # DeployConfig represents the root deployment configuration
    class DeployConfig
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
        @domain_provider = DomainProviderConfig.new(data["domain_provider"] || {})
        @compute_provider = ComputeProviderConfig.new(data["compute_provider"] || {})
        @keep_count = data["keep_count"]&.to_i
        @servers = parse_servers(data["servers"] || {})
        @app = parse_app_config(data["app"] || {})
        @database = data["database"] ? DatabaseConfig.new(data["database"]) : nil
        @services = parse_services(data["services"] || {})
        @env = data["env"] || {}
        @secrets = data["secrets"] || {}
        @ssh_keys = data["ssh_keys"] ? SSHKeyConfig.new(data["ssh_keys"]) : nil
      end

      private

        def parse_servers(data)
          data.transform_values { |v| ServerConfig.new(v || {}) }
        end

        def parse_app_config(data)
          data.transform_values { |v| AppServiceConfig.new(v || {}) }
        end

        def parse_services(data)
          data.transform_values { |v| ServiceConfig.new(v || {}) }
        end
    end

    # DomainProviderConfig contains domain provider configuration
    class DomainProviderConfig
      attr_accessor :cloudflare

      def initialize(data = {})
        @cloudflare = data["cloudflare"] ? CloudflareConfig.new(data["cloudflare"]) : nil
      end
    end

    # ComputeProviderConfig contains compute provider configuration
    class ComputeProviderConfig
      attr_accessor :hetzner, :aws

      def initialize(data = {})
        @hetzner = data["hetzner"] ? HetznerConfig.new(data["hetzner"]) : nil
        @aws = data["aws"] ? AWSConfig.new(data["aws"]) : nil
      end
    end

    # CloudflareConfig contains Cloudflare-specific configuration
    class CloudflareConfig
      attr_accessor :api_token, :account_id

      def initialize(data = {})
        @api_token = data["api_token"]
        @account_id = data["account_id"]
      end
    end

    # HetznerConfig contains Hetzner-specific configuration
    class HetznerConfig
      attr_accessor :api_token, :server_type, :server_location

      def initialize(data = {})
        @api_token = data["api_token"]
        @server_type = data["server_type"]
        @server_location = data["server_location"]
      end
    end

    # AWSConfig contains AWS-specific configuration
    class AWSConfig
      attr_accessor :access_key_id, :secret_access_key, :region, :instance_type

      def initialize(data = {})
        @access_key_id = data["access_key_id"]
        @secret_access_key = data["secret_access_key"]
        @region = data["region"]
        @instance_type = data["instance_type"]
      end
    end

    # ServerVolumeConfig defines a volume attached to a server
    class ServerVolumeConfig
      attr_accessor :size

      def initialize(data = {})
        # Handle both hash format { "size" => 20 } and integer format
        if data.is_a?(Hash)
          @size = data["size"]&.to_i || 10
        else
          @size = data.to_i.positive? ? data.to_i : 10
        end
      end
    end

    # ServerConfig contains server instance configuration
    class ServerConfig
      attr_accessor :master, :type, :location, :count, :volumes

      def initialize(data = {})
        @master = data["master"] || false
        @type = data["type"]
        @location = data["location"]
        @count = data["count"]&.to_i || 1
        @volumes = parse_volumes(data["volumes"] || {})
      end

      private

        def parse_volumes(data)
          data.transform_values { |v| ServerVolumeConfig.new(v || {}) }
        end
    end

    # AppServiceConfig defines a service in the app section
    class AppServiceConfig
      attr_accessor :servers, :domain, :subdomain, :port, :healthcheck,
                    :command, :pre_run_command, :env, :mounts

      def initialize(data = {})
        @servers = data["servers"] || []
        @domain = data["domain"]
        @subdomain = data["subdomain"]
        @port = data["port"]&.to_i
        @healthcheck = data["healthcheck"] ? HealthCheckConfig.new(data["healthcheck"]) : nil
        @command = data["command"]
        @pre_run_command = data["pre_run_command"]
        @env = data["env"] || {}
        @mounts = data["mounts"] || {}
      end

      # Convert to ServiceSpec
      def to_service_spec(app_name, service_name, image_tag)
        cmd = @command ? @command.split : []

        spec = ServiceSpec.new(
          name: "#{app_name}-#{service_name}",
          image: image_tag,
          port: @port,
          command: cmd,
          env: @env,
          mounts: @mounts,
          replicas: @port.nil? || @port.zero? ? 1 : 2,
          healthcheck: @healthcheck,
          stateful_set: false,
          servers: @servers
        )
        spec
      end
    end

    # HealthCheckConfig defines health check configuration
    class HealthCheckConfig
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

    # DatabaseConfig defines database configuration
    class DatabaseConfig
      attr_accessor :servers, :adapter, :url, :image, :mount, :secrets

      def initialize(data = {})
        @servers = data["servers"] || []
        @adapter = data["adapter"]
        @url = data["url"]
        @image = data["image"]
        @mount = data["mount"] || {}
        @secrets = data["secrets"] || {}
      end

      # Convert to ServiceSpec
      def to_service_spec(namer)
        port = case @adapter&.downcase
        when "mysql" then 3306
        else 5432
        end

        ServiceSpec.new(
          name: namer.database_service_name,
          image: @image,
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

    # ServiceConfig defines a generic service
    class ServiceConfig
      attr_accessor :servers, :image, :command, :env, :mount

      def initialize(data = {})
        @servers = data["servers"] || []
        @image = data["image"]
        @command = data["command"]
        @env = data["env"] || {}
        @mount = data["mount"] || {}
      end

      # Convert to ServiceSpec
      def to_service_spec(app_name, service_name)
        cmd = @command ? @command.split : []

        # Infer port from image
        port = case @image
        when /redis/ then 6379
        when /postgres/ then 5432
        when /mysql/ then 3306
        else 0
        end

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
    end

    # SSHKeyConfig defines SSH key content (stored in encrypted config)
    class SSHKeyConfig
      attr_accessor :private_key, :public_key

      def initialize(data = {})
        @private_key = data["private_key"]
        @public_key = data["public_key"]
      end
    end

    # ServiceSpec is the CORE primitive - pure K8s deployment specification
    class ServiceSpec
      attr_accessor :name, :image, :port, :command, :env, :mounts, :replicas,
                    :healthcheck, :stateful_set, :secrets, :servers

      def initialize(name:, image:, port: 0, command: [], env: nil, mounts: nil,
                     replicas: 1, healthcheck: nil, stateful_set: false, secrets: nil, servers: [])
        @name = name
        @image = image
        @port = port
        @command = command || []
        @env = env || {}
        @mounts = mounts || {}
        @replicas = replicas
        @healthcheck = healthcheck
        @stateful_set = stateful_set
        @secrets = secrets || {}
        @servers = servers || []
      end
    end
  end
end
