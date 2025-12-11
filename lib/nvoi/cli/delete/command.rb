# frozen_string_literal: true

module Nvoi
  class Cli
    module Delete
      # Command handles cleanup of all cloud resources
      class Command
        def initialize(options)
          @options = options
          @log = Nvoi.logger
        end

        def run
          @log.info "Delete CLI %s", VERSION

          # Load configuration
          config_path = resolve_config_path
          @config = Utils::ConfigLoader.load(config_path)

          # Apply branch override if specified
          apply_branch_override if @options[:branch]

          # Initialize cloud provider
          @provider = External::Cloud.for(@config)

          # Initialize Cloudflare client
          cf = @config.cloudflare
          @cf_client = External::Dns::Cloudflare.new(cf.api_token, cf.account_id)

          @log.info "Using %s Cloud provider", @config.provider_name

          # Run teardown steps in order
          require_relative "steps/detach_volumes"
          require_relative "steps/teardown_server"
          require_relative "steps/teardown_volume"
          require_relative "steps/teardown_firewall"
          require_relative "steps/teardown_network"
          require_relative "steps/teardown_tunnel"
          require_relative "steps/teardown_dns"

          Steps::DetachVolumes.new(@config, @provider, @log).run
          Steps::TeardownServer.new(@config, @provider, @log).run
          Steps::TeardownVolume.new(@config, @provider, @log).run
          Steps::TeardownFirewall.new(@config, @provider, @log).run
          Steps::TeardownNetwork.new(@config, @provider, @log).run
          Steps::TeardownTunnel.new(@config, @cf_client, @log).run
          Steps::TeardownDns.new(@config, @cf_client, @log).run

          @log.success "Cleanup complete"
        end

        private

          def resolve_config_path
            config_path = @options[:config] || "deploy.enc"
            working_dir = @options[:dir]

            if config_path == "deploy.enc" && working_dir && working_dir != "."
              File.join(working_dir, "deploy.enc")
            else
              config_path
            end
          end

          def apply_branch_override
            branch = @options[:branch]
            return if branch.nil? || branch.empty?

            override = Objects::ConfigOverride.new(branch: branch)
            override.apply(@config)
          end
      end
    end
  end
end
