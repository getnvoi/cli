# frozen_string_literal: true

module Nvoi
  module Steps
    # ApplicationDeployer orchestrates the full application deployment
    class ApplicationDeployer
      def initialize(config, provider, working_dir, server_ip, tunnels, log)
        @config = config
        @provider = provider
        @working_dir = working_dir
        @server_ip = server_ip
        @tunnels = tunnels
        @log = log
      end

      def run
        @log.info "Deploying application"

        orchestrator = Deployer::Orchestrator.new(@config, @provider, @log)
        orchestrator.run(@server_ip, @tunnels, @working_dir)

        @log.success "Application deployed"
      end
    end
  end
end
