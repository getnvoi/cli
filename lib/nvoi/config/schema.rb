# frozen_string_literal: true

module Nvoi
  module Config
    # ConfigSchema provides UI-driven form definitions for building deployment configs.
    # Used by Rails app to dynamically render forms for each configuration step.
    class Schema
      STEPS = [
        {
          key: :compute_provider,
          title: "Compute Provider",
          description: "Select your cloud provider for server provisioning",
          required: true,
          depends_on: [],
          fields: [
            {
              key: :provider,
              type: :select,
              label: "Provider",
              required: true,
              options: [
                { value: :hetzner, label: "Hetzner Cloud" },
                { value: :aws, label: "AWS" }
              ]
            },
            {
              key: :api_token,
              type: :string,
              label: "API Token",
              required: true,
              secret: true,
              show_if: { field: :provider, equals: :hetzner }
            },
            {
              key: :access_key_id,
              type: :string,
              label: "Access Key ID",
              required: true,
              show_if: { field: :provider, equals: :aws }
            },
            {
              key: :secret_access_key,
              type: :string,
              label: "Secret Access Key",
              required: true,
              secret: true,
              show_if: { field: :provider, equals: :aws }
            },
            {
              key: :region,
              type: :select,
              label: "Region",
              required: true,
              options_from: :aws_regions,
              show_if: { field: :provider, equals: :aws }
            },
            {
              key: :server_type,
              type: :select,
              label: "Default Server Type",
              required: false,
              options_from: :provider_server_types,
              description: "Default server type for all server groups"
            },
            {
              key: :server_location,
              type: :select,
              label: "Default Location",
              required: false,
              options_from: :provider_locations,
              description: "Default datacenter location",
              show_if: { field: :provider, equals: :hetzner }
            }
          ]
        },
        {
          key: :domain_provider,
          title: "Domain Provider",
          description: "Configure DNS and tunnel provider",
          required: true,
          depends_on: [],
          fields: [
            {
              key: :provider,
              type: :select,
              label: "Provider",
              required: true,
              options: [
                { value: :cloudflare, label: "Cloudflare" }
              ]
            },
            {
              key: :api_token,
              type: :string,
              label: "API Token",
              required: true,
              secret: true,
              description: "Cloudflare API token with DNS and Tunnel permissions"
            },
            {
              key: :account_id,
              type: :string,
              label: "Account ID",
              required: true,
              description: "Your Cloudflare account ID"
            }
          ]
        },
        {
          key: :servers,
          title: "Servers",
          description: "Define server groups for your deployment",
          required: true,
          depends_on: [:compute_provider],
          collection: true,
          min_items: 1,
          item_key_field: :name,
          fields: [
            {
              key: :name,
              type: :string,
              label: "Group Name",
              required: true,
              placeholder: "e.g., master, workers",
              validation: { pattern: "^[a-z][a-z0-9-]*$" }
            },
            {
              key: :master,
              type: :boolean,
              label: "Master Node",
              default: false,
              description: "Whether this group contains the K3s master"
            },
            {
              key: :type,
              type: :select,
              label: "Server Type",
              options_from: :provider_server_types,
              description: "Overrides default server type"
            },
            {
              key: :location,
              type: :select,
              label: "Location",
              options_from: :provider_locations,
              description: "Overrides default location"
            },
            {
              key: :count,
              type: :number,
              label: "Count",
              default: 1,
              validation: { min: 1, max: 10 }
            },
            {
              key: :volumes,
              type: :collection,
              label: "Volumes",
              description: "Block storage volumes attached to this server",
              item_fields: [
                {
                  key: :name,
                  type: :string,
                  label: "Volume Name",
                  required: true,
                  validation: { pattern: "^[a-z][a-z0-9-]*$" }
                },
                {
                  key: :size,
                  type: :number,
                  label: "Size (GB)",
                  default: 10,
                  validation: { min: 10, max: 10_000 }
                }
              ]
            }
          ]
        },
        {
          key: :database,
          title: "Database",
          description: "Configure database for your application",
          required: false,
          depends_on: [:servers],
          fields: [
            {
              key: :adapter,
              type: :select,
              label: "Database Type",
              required: true,
              options: [
                { value: :postgres, label: "PostgreSQL" },
                { value: :mysql, label: "MySQL" },
                { value: :sqlite3, label: "SQLite (embedded)" }
              ]
            },
            {
              key: :servers,
              type: :multiselect,
              label: "Server Groups",
              required: true,
              options_from: :defined_servers,
              description: "Server groups to run the database on"
            },
            {
              key: :image,
              type: :string,
              label: "Docker Image",
              placeholder: "postgres:15-alpine",
              show_if: { field: :adapter, not_equals: :sqlite3 }
            },
            {
              key: :url,
              type: :string,
              label: "Database URL",
              placeholder: "postgres://user:pass@host:5432/dbname",
              description: "Custom DATABASE_URL (overrides auto-generated URL)",
              show_if: { field: :adapter, not_equals: :sqlite3 }
            },
            {
              key: :mount,
              type: :key_value,
              label: "Volume Mount",
              description: "Mount a server volume for data persistence",
              key_options_from: :server_volumes,
              value_placeholder: "/var/lib/postgresql/data",
              show_if: { field: :adapter, not_equals: :sqlite3 }
            },
            {
              key: :secrets,
              type: :key_value,
              label: "Database Secrets",
              description: "Environment variables for database (e.g., POSTGRES_PASSWORD)",
              secret_values: true,
              show_if: { field: :adapter, not_equals: :sqlite3 }
            }
          ]
        },
        {
          key: :services,
          title: "Services",
          description: "Additional services like Redis, Memcached, etc.",
          required: false,
          depends_on: [:servers],
          collection: true,
          min_items: 0,
          item_key_field: :name,
          fields: [
            {
              key: :name,
              type: :string,
              label: "Service Name",
              required: true,
              placeholder: "e.g., redis, memcached"
            },
            {
              key: :servers,
              type: :multiselect,
              label: "Server Groups",
              required: true,
              options_from: :defined_servers
            },
            {
              key: :image,
              type: :string,
              label: "Docker Image",
              required: true,
              placeholder: "redis:7-alpine"
            },
            {
              key: :port,
              type: :number,
              label: "Port",
              placeholder: "6379",
              description: "Service port (auto-detected from image if not specified)"
            },
            {
              key: :command,
              type: :string,
              label: "Command Override",
              placeholder: "redis-server --appendonly yes"
            },
            {
              key: :env,
              type: :key_value,
              label: "Environment Variables"
            },
            {
              key: :mount,
              type: :key_value,
              label: "Volume Mount",
              key_options_from: :server_volumes,
              value_placeholder: "/data"
            }
          ]
        },
        {
          key: :app_services,
          title: "Application Services",
          description: "Define your application services (web, worker, etc.)",
          required: true,
          depends_on: [:servers, :domain_provider],
          collection: true,
          min_items: 1,
          item_key_field: :name,
          fields: [
            {
              key: :name,
              type: :string,
              label: "Service Name",
              required: true,
              placeholder: "e.g., web, worker, api"
            },
            {
              key: :servers,
              type: :multiselect,
              label: "Server Groups",
              required: true,
              options_from: :defined_servers,
              description: "Note: services with mounts can only run on a single server"
            },
            {
              key: :port,
              type: :number,
              label: "Container Port",
              placeholder: "3000",
              description: "Leave empty for background workers"
            },
            {
              key: :domain,
              type: :string,
              label: "Domain",
              placeholder: "example.com",
              description: "Domain for this service (must be on Cloudflare)"
            },
            {
              key: :subdomain,
              type: :string,
              label: "Subdomain",
              placeholder: "www or @ for apex",
              description: "Use @ for the root domain"
            },
            {
              key: :command,
              type: :string,
              label: "Command Override",
              placeholder: "bundle exec puma -C config/puma.rb"
            },
            {
              key: :pre_run_command,
              type: :string,
              label: "Pre-run Command",
              placeholder: "bundle exec rails db:migrate",
              description: "Command to run before deployment (e.g., migrations)"
            },
            {
              key: :healthcheck,
              type: :group,
              label: "Health Check",
              fields: [
                {
                  key: :type,
                  type: :select,
                  label: "Type",
                  options: [
                    { value: :http, label: "HTTP" },
                    { value: :tcp, label: "TCP" },
                    { value: :exec, label: "Command" }
                  ]
                },
                {
                  key: :path,
                  type: :string,
                  label: "Path",
                  placeholder: "/health",
                  show_if: { field: :type, equals: :http }
                },
                {
                  key: :port,
                  type: :number,
                  label: "Port",
                  description: "Defaults to service port"
                },
                {
                  key: :command,
                  type: :string,
                  label: "Command",
                  show_if: { field: :type, equals: :exec }
                }
              ]
            },
            {
              key: :env,
              type: :key_value,
              label: "Service-specific Environment"
            },
            {
              key: :mounts,
              type: :key_value,
              label: "Volume Mounts",
              description: "Mount server volumes (volume_name: mount_path)",
              key_options_from: :server_volumes,
              value_placeholder: "/app/data"
            }
          ]
        },
        {
          key: :env,
          title: "Environment Variables",
          description: "Global environment variables for all services",
          required: false,
          depends_on: [],
          fields: [
            {
              key: :variables,
              type: :key_value,
              label: "Environment Variables",
              description: "Key-value pairs available to all services"
            }
          ]
        },
        {
          key: :secrets,
          title: "Secrets",
          description: "Secret environment variables (stored encrypted)",
          required: false,
          depends_on: [],
          fields: [
            {
              key: :variables,
              type: :key_value,
              label: "Secret Variables",
              description: "These values will be encrypted in your deploy.enc file",
              secret_values: true
            }
          ]
        }
      ].freeze

      # Static options for providers
      HETZNER_LOCATIONS = [
        { value: "fsn1", label: "Falkenstein, Germany (fsn1)" },
        { value: "nbg1", label: "Nuremberg, Germany (nbg1)" },
        { value: "hel1", label: "Helsinki, Finland (hel1)" },
        { value: "ash", label: "Ashburn, USA (ash)" },
        { value: "hil", label: "Hillsboro, USA (hil)" }
      ].freeze

      HETZNER_SERVER_TYPES = [
        { value: "cx22", label: "CX22 - 2 vCPU, 4GB RAM" },
        { value: "cx32", label: "CX32 - 4 vCPU, 8GB RAM" },
        { value: "cx42", label: "CX42 - 8 vCPU, 16GB RAM" },
        { value: "cx52", label: "CX52 - 16 vCPU, 32GB RAM" }
      ].freeze

      AWS_REGIONS = [
        { value: "us-east-1", label: "US East (N. Virginia)" },
        { value: "us-east-2", label: "US East (Ohio)" },
        { value: "us-west-1", label: "US West (N. California)" },
        { value: "us-west-2", label: "US West (Oregon)" },
        { value: "eu-west-1", label: "EU (Ireland)" },
        { value: "eu-central-1", label: "EU (Frankfurt)" },
        { value: "ap-northeast-1", label: "Asia Pacific (Tokyo)" },
        { value: "ap-southeast-1", label: "Asia Pacific (Singapore)" }
      ].freeze

      AWS_INSTANCE_TYPES = [
        { value: "t3.micro", label: "t3.micro - 2 vCPU, 1GB RAM" },
        { value: "t3.small", label: "t3.small - 2 vCPU, 2GB RAM" },
        { value: "t3.medium", label: "t3.medium - 2 vCPU, 4GB RAM" },
        { value: "t3.large", label: "t3.large - 2 vCPU, 8GB RAM" },
        { value: "t3.xlarge", label: "t3.xlarge - 4 vCPU, 16GB RAM" }
      ].freeze

      class << self
        # Returns all step definitions
        def steps
          STEPS
        end

        # Get a specific step by key
        def step(key)
          STEPS.find { |s| s[:key] == key }
        end

        # Fetch dynamic options based on current config
        # @param option_key [Symbol] The option key to fetch
        # @param config [Hash] Current config state
        # @param context [Hash] Additional context (e.g., { server: "master" })
        # @return [Array<Hash>] Array of { value:, label: } options
        def fetch_options(option_key, config, context = {})
          case option_key
          when :provider_server_types
            fetch_server_types(config)
          when :provider_locations
            fetch_locations(config)
          when :aws_regions
            AWS_REGIONS
          when :defined_servers
            fetch_defined_servers(config)
          when :server_volumes
            fetch_server_volumes(config, context[:server])
          else
            []
          end
        end

        private

          def fetch_server_types(config)
            provider = detect_provider(config)
            case provider
            when :hetzner
              HETZNER_SERVER_TYPES
            when :aws
              AWS_INSTANCE_TYPES
            else
              []
            end
          end

          def fetch_locations(config)
            provider = detect_provider(config)
            case provider
            when :hetzner
              HETZNER_LOCATIONS
            when :aws
              AWS_REGIONS
            else
              []
            end
          end

          def fetch_defined_servers(config)
            servers = config.dig("application", "servers") || {}
            servers.keys.map { |name| { value: name, label: name } }
          end

          def fetch_server_volumes(config, server_name = nil)
            servers = config.dig("application", "servers") || {}

            if server_name
              # Volumes for a specific server
              volumes = servers.dig(server_name, "volumes") || {}
              volumes.map do |name, vol|
                size = vol["size"] || 10
                { value: name, label: "#{name} (#{size}GB)" }
              end
            else
              # All volumes across all servers
              all_volumes = []
              servers.each do |srv_name, srv_config|
                (srv_config["volumes"] || {}).each do |vol_name, vol|
                  size = vol["size"] || 10
                  all_volumes << {
                    value: vol_name,
                    label: "#{srv_name}/#{vol_name} (#{size}GB)",
                    server: srv_name
                  }
                end
              end
              all_volumes
            end
          end

          def detect_provider(config)
            cp = config.dig("application", "compute_provider") || {}
            return :hetzner if cp["hetzner"]
            return :aws if cp["aws"]

            nil
          end
      end
    end
  end
end
