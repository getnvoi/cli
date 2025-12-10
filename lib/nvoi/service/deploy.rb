# frozen_string_literal: true

module Nvoi
  module Service
    # DeployService orchestrates the deployment process
    class DeployService
      include ProviderHelper

      attr_accessor :config_dir, :dockerfile_path

      def initialize(config_path, working_dir, log, override: nil)
        @working_dir = working_dir
        @log = log

        # Load configuration
        @config = Config.load(config_path)

        # Apply override for branch deployments
        override&.apply(@config)

        # Initialize provider
        @provider = init_provider(@config)

        # Validate provider-specific configuration
        validate_provider_config(@config, @provider)

        @log.info "Using %s Cloud provider", @config.provider_name
      end

      def run
        @log.info "Starting deployment"
        @log.separator

        # Step 1: Provision server
        server_ip = provision_server
        raise DeploymentError.new("server provisioning", "failed") unless server_ip

        # Step 2: Configure tunnels
        tunnels = configure_tunnels

        # Step 3: Deploy application
        deploy_application(server_ip, tunnels)

        # Success
        @log.separator
        @log.success "Deployment complete"

        # Log service URLs
        tunnels.each do |tunnel|
          @log.info "Service %s: https://%s", tunnel.service_name, tunnel.hostname
        end
      end

      private

        def provision_server
          # Step 1: Provision all servers (main + workers)
          provisioner = Steps::ServerProvisioner.new(@config, @provider, @log)
          main_server_ip = provisioner.run

          # Step 2: Provision volumes (create, attach, mount)
          volume_provisioner = Steps::VolumeProvisioner.new(@config, @provider, @log)
          volume_provisioner.run

          # Step 3: Setup K3s cluster (main server + join workers)
          cluster_setup = Steps::K3sClusterSetup.new(@config, @provider, @log, main_server_ip)
          cluster_setup.run

          main_server_ip
        end

        def configure_tunnels
          configurator = Steps::TunnelConfigurator.new(@config, @log)
          configurator.run
        end

        def deploy_application(server_ip, tunnels)
          app_deployer = Steps::ApplicationDeployer.new(@config, @provider, @working_dir, server_ip, tunnels, @log)
          app_deployer.run
        end
    end
  end
end
