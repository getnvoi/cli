# frozen_string_literal: true

module Nvoi
  module Steps
    # ServerProvisioner handles provisioning of compute servers
    class ServerProvisioner
      def initialize(config, provider, log)
        @config = config
        @provider = provider
        @log = log
        @infrastructure = Deployer::Infrastructure.new(config, provider, log)
      end

      # Run provisions all servers and returns the main server IP
      def run
        @log.info "Provisioning servers"

        # Provision network and firewall
        network = @infrastructure.provision_network
        firewall = @infrastructure.provision_firewall

        servers = @config.deploy.application.servers
        main_server_ip = nil

        # Provision each server group
        servers.each do |group_name, group_config|
          count = group_config&.count&.positive? ? group_config.count : 1

          (1..count).each do |i|
            server_name = @config.namer.server_name(group_name, i)
            server = @infrastructure.provision_server(server_name, network.id, firewall.id, group_config)

            # Track main server IP (first master, or just first server)
            main_server_ip ||= server.public_ipv4 if group_config&.master || i == 1
          end
        end

        @log.success "All servers provisioned"
        main_server_ip
      end
    end
  end
end
