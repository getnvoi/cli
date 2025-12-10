# frozen_string_literal: true

module Nvoi
  module Config
    # ConfigBuilder provides a stateless API for building deployment configurations.
    # Each method takes the current config state and returns a new config (or raises an error).
    # The Rails app owns the state; this module provides pure functions.
    module Builder
      # Step definitions with dependencies
      STEPS = [
        { key: :compute_provider, required: true, depends_on: [] },
        { key: :domain_provider, required: true, depends_on: [] },
        { key: :servers, required: true, depends_on: [:compute_provider] },
        { key: :database, required: false, depends_on: [:servers] },
        { key: :services, required: false, depends_on: [:servers] },
        { key: :app_services, required: true, depends_on: [:servers, :domain_provider] },
        { key: :env, required: false, depends_on: [] },
        { key: :secrets, required: false, depends_on: [] }
      ].freeze

      class DependencyError < StandardError; end
      class ValidationError < StandardError; end

      class << self
        # Returns step definitions
        def steps
          STEPS
        end

        # Analyze config status
        # @param config [Hash] Current config state
        # @return [Hash] Status including completed steps, readiness, and errors
        def status(config)
          config = normalize_config(config)
          step_status = {}
          errors = []

          STEPS.each do |step|
            completed = step_completed?(config, step[:key])
            deps_met = step[:depends_on].all? { |dep| step_completed?(config, dep) }
            step_status[step[:key]] = {
              completed:,
              deps_met:,
              required: step[:required],
              available: deps_met
            }
          end

          # Find next required step
          next_required = STEPS.find do |step|
            step[:required] && !step_status[step[:key]][:completed] && step_status[step[:key]][:deps_met]
          end&.fetch(:key)

          # Check if ready for deploy
          ready = STEPS.all? do |step|
            !step[:required] || step_status[step[:key]][:completed]
          end

          # Validate mounts if servers and app_services are set
          if step_status[:servers][:completed] && step_status[:app_services][:completed]
            errors.concat(validate_mounts(config))
          end

          {
            steps: step_status,
            ready_for_deploy: ready && errors.empty?,
            next_required:,
            errors:
          }
        end

        # Set compute provider configuration
        # @param config [Hash] Current config
        # @param data [Hash] Provider data (e.g., { provider: :hetzner, api_token: "...", ... })
        # @return [Hash] Updated config
        def set_compute_provider(config, data)
          config = deep_dup(normalize_config(config))
          provider = data[:provider]&.to_sym

          case provider
          when :hetzner
            config["application"]["compute_provider"] = {
              "hetzner" => {
                "api_token" => data[:api_token],
                "server_type" => data[:server_type],
                "server_location" => data[:server_location]
              }.compact
            }
          when :aws
            config["application"]["compute_provider"] = {
              "aws" => {
                "access_key_id" => data[:access_key_id],
                "secret_access_key" => data[:secret_access_key],
                "region" => data[:region],
                "instance_type" => data[:instance_type]
              }.compact
            }
          else
            raise ValidationError, "Unknown compute provider: #{provider}"
          end

          config
        end

        # Set domain provider configuration
        # @param config [Hash] Current config
        # @param data [Hash] Provider data
        # @return [Hash] Updated config
        def set_domain_provider(config, data)
          config = deep_dup(normalize_config(config))
          provider = data[:provider]&.to_sym

          case provider
          when :cloudflare
            config["application"]["domain_provider"] = {
              "cloudflare" => {
                "api_token" => data[:api_token],
                "account_id" => data[:account_id]
              }.compact
            }
          else
            raise ValidationError, "Unknown domain provider: #{provider}"
          end

          config
        end

        # Set servers configuration
        # @param config [Hash] Current config
        # @param data [Hash] Servers data (e.g., { master: { type: "cx22", volumes: { db: { size: 20 } } } })
        # @return [Hash] Updated config
        def set_servers(config, data)
          config = deep_dup(normalize_config(config))
          check_dependencies!(config, :servers)

          servers = {}
          data.each do |name, server_data|
            name = name.to_s
            servers[name] = {
              "master" => server_data[:master] || false,
              "type" => server_data[:type],
              "location" => server_data[:location],
              "count" => server_data[:count] || 1
            }.compact

            if server_data[:volumes]
              servers[name]["volumes"] = {}
              server_data[:volumes].each do |vol_name, vol_data|
                servers[name]["volumes"][vol_name.to_s] = {
                  "size" => vol_data[:size] || 10
                }
              end
            end
          end

          # Ensure at least one master
          has_master = servers.values.any? { |s| s["master"] }
          servers[servers.keys.first]["master"] = true unless has_master

          config["application"]["servers"] = servers
          config
        end

        # Set database configuration
        # @param config [Hash] Current config
        # @param data [Hash, nil] Database data (nil to remove)
        # @return [Hash] Updated config
        def set_database(config, data)
          config = deep_dup(normalize_config(config))
          check_dependencies!(config, :database)

          if data.nil? || data.empty?
            config["application"].delete("database")
            return config
          end

          db = {
            "servers" => Array(data[:servers]).map(&:to_s),
            "adapter" => data[:adapter]
          }

          db["url"] = data[:url] if data[:url]
          db["image"] = data[:image] if data[:image]
          db["secrets"] = stringify_keys(data[:secrets]) if data[:secrets]

          # Mount references a server volume
          if data[:mount]
            db["mount"] = stringify_keys(data[:mount])
          end

          config["application"]["database"] = db
          config
        end

        # Set additional services (redis, etc.)
        # @param config [Hash] Current config
        # @param data [Hash] Services data
        # @return [Hash] Updated config
        def set_services(config, data)
          config = deep_dup(normalize_config(config))
          check_dependencies!(config, :services)

          services = {}
          data.each do |name, svc_data|
            name = name.to_s
            services[name] = {
              "servers" => Array(svc_data[:servers]).map(&:to_s),
              "image" => svc_data[:image]
            }
            services[name]["command"] = svc_data[:command] if svc_data[:command]
            services[name]["env"] = stringify_keys(svc_data[:env]) if svc_data[:env]
            services[name]["mount"] = stringify_keys(svc_data[:mount]) if svc_data[:mount]
          end

          config["application"]["services"] = services
          config
        end

        # Set app services (web, worker, etc.)
        # @param config [Hash] Current config
        # @param data [Hash] App services data
        # @return [Hash] Updated config
        def set_app_services(config, data)
          config = deep_dup(normalize_config(config))
          check_dependencies!(config, :app_services)

          app = {}
          data.each do |name, svc_data|
            name = name.to_s
            app[name] = {
              "servers" => Array(svc_data[:servers]).map(&:to_s)
            }

            app[name]["domain"] = svc_data[:domain] if svc_data[:domain]
            app[name]["subdomain"] = svc_data[:subdomain] if svc_data[:subdomain]
            app[name]["port"] = svc_data[:port].to_i if svc_data[:port]
            app[name]["command"] = svc_data[:command] if svc_data[:command]
            app[name]["pre_run_command"] = svc_data[:pre_run_command] if svc_data[:pre_run_command]
            app[name]["env"] = stringify_keys(svc_data[:env]) if svc_data[:env]
            app[name]["mounts"] = stringify_keys(svc_data[:mounts]) if svc_data[:mounts]

            if svc_data[:healthcheck]
              app[name]["healthcheck"] = stringify_keys(svc_data[:healthcheck])
            end
          end

          config["application"]["app"] = app
          config
        end

        # Set environment variables
        # @param config [Hash] Current config
        # @param data [Hash] Environment variables
        # @return [Hash] Updated config
        def set_env(config, data)
          config = deep_dup(normalize_config(config))
          config["application"]["env"] = stringify_keys(data || {})
          config
        end

        # Set secrets
        # @param config [Hash] Current config
        # @param data [Hash] Secret environment variables
        # @return [Hash] Updated config
        def set_secrets(config, data)
          config = deep_dup(normalize_config(config))
          config["application"]["secrets"] = stringify_keys(data || {})
          config
        end

        # Set application name
        # @param config [Hash] Current config
        # @param name [String] Application name
        # @return [Hash] Updated config
        def set_name(config, name)
          config = deep_dup(normalize_config(config))
          config["application"]["name"] = name
          config
        end

        # Set keep_count (number of old deployments to keep)
        # @param config [Hash] Current config
        # @param count [Integer] Number to keep
        # @return [Hash] Updated config
        def set_keep_count(config, count)
          config = deep_dup(normalize_config(config))
          config["application"]["keep_count"] = count.to_i
          config
        end

        private

          def normalize_config(config)
            config = config || {}
            config = deep_dup(config)
            config["application"] ||= {}
            config
          end

          def deep_dup(obj)
            case obj
            when Hash
              obj.transform_values { |v| deep_dup(v) }
            when Array
              obj.map { |v| deep_dup(v) }
            else
              obj.dup rescue obj
            end
          end

          def stringify_keys(hash)
            return {} unless hash

            hash.transform_keys(&:to_s)
          end

          def step_completed?(config, step_key)
            app = config["application"] || {}

            case step_key
            when :compute_provider
              cp = app["compute_provider"]
              cp && (cp["hetzner"] || cp["aws"])
            when :domain_provider
              dp = app["domain_provider"]
              dp && dp["cloudflare"]
            when :servers
              servers = app["servers"]
              servers && !servers.empty?
            when :database
              # Database is optional, so always "completed" if not required
              true
            when :services
              # Services are optional
              true
            when :app_services
              app_cfg = app["app"]
              app_cfg && !app_cfg.empty?
            when :env
              # Env is optional
              true
            when :secrets
              # Secrets are optional
              true
            else
              false
            end
          end

          def check_dependencies!(config, step_key)
            step = STEPS.find { |s| s[:key] == step_key }
            return unless step

            step[:depends_on].each do |dep|
              unless step_completed?(config, dep)
                raise DependencyError, "Step '#{step_key}' requires '#{dep}' to be configured first"
              end
            end
          end

          def validate_mounts(config)
            errors = []
            app = config["application"] || {}
            servers = app["servers"] || {}

            # Validate app service mounts
            (app["app"] || {}).each do |svc_name, svc_config|
              mounts = svc_config["mounts"]
              next unless mounts && !mounts.empty?

              svc_servers = svc_config["servers"] || []

              # Multi-server with mounts is invalid
              if svc_servers.length > 1
                errors << "app '#{svc_name}' runs on multiple servers #{svc_servers} and cannot have mounts. " \
                          "Volumes are server-local and would cause data inconsistency."
                next
              end

              server_name = svc_servers.first
              server_config = servers[server_name]

              mounts.each_key do |vol_name|
                server_volumes = server_config&.dig("volumes") || {}
                unless server_volumes.key?(vol_name)
                  available = server_volumes.keys.join(", ")
                  available = "none" if available.empty?
                  errors << "app '#{svc_name}' mounts '#{vol_name}' but server '#{server_name}' " \
                            "has no volume named '#{vol_name}'. Available: #{available}"
                end
              end
            end

            # Validate database mount
            db = app["database"]
            if db && db["mount"] && !db["mount"].empty?
              db_servers = db["servers"] || []
              server_name = db_servers.first
              server_config = servers[server_name]

              db["mount"].each_key do |vol_name|
                server_volumes = server_config&.dig("volumes") || {}
                unless server_volumes.key?(vol_name)
                  available = server_volumes.keys.join(", ")
                  available = "none" if available.empty?
                  errors << "database mounts '#{vol_name}' but server '#{server_name}' " \
                            "has no volume named '#{vol_name}'. Available: #{available}"
                end
              end
            end

            # Validate service mounts
            (app["services"] || {}).each do |svc_name, svc_config|
              mount = svc_config["mount"]
              next unless mount && !mount.empty?

              svc_servers = svc_config["servers"] || []
              server_name = svc_servers.first
              server_config = servers[server_name]

              mount.each_key do |vol_name|
                server_volumes = server_config&.dig("volumes") || {}
                unless server_volumes.key?(vol_name)
                  available = server_volumes.keys.join(", ")
                  available = "none" if available.empty?
                  errors << "service '#{svc_name}' mounts '#{vol_name}' but server '#{server_name}' " \
                            "has no volume named '#{vol_name}'. Available: #{available}"
                end
              end
            end

            errors
          end
      end
    end
  end
end
