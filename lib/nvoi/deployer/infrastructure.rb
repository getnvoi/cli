# frozen_string_literal: true

module Nvoi
  module Deployer
    # Infrastructure handles cloud resource provisioning
    class Infrastructure
      def initialize(config, provider, log)
        @config = config
        @provider = provider
        @log = log
      end

      def provision_network
        @log.info "Provisioning network: %s", @config.network_name
        network = @provider.find_or_create_network(@config.network_name)
        @log.success "Network ready: %s", network.id
        network
      end

      def provision_firewall
        @log.info "Provisioning firewall: %s", @config.firewall_name
        firewall = @provider.find_or_create_firewall(@config.firewall_name)
        @log.success "Firewall ready: %s", firewall.id
        firewall
      end

      def provision_server(name, network_id, firewall_id, server_config)
        @log.info "Provisioning server: %s", name

        # Check if server already exists
        existing = @provider.find_server(name)
        if existing
          @log.info "Server already exists: %s (%s)", name, existing.public_ipv4
          return existing
        end

        # Determine server type and location
        server_type = server_config&.type
        location = server_config&.location

        case @config.provider_name
        when "hetzner"
          h = @config.hetzner
          server_type ||= h.server_type
          location ||= h.server_location
          image = "ubuntu-22.04"
        when "aws"
          a = @config.aws
          server_type ||= a.instance_type
          location ||= a.region
          image = "ubuntu-22.04"
        end

        # Create cloud-init user data
        user_data = generate_user_data

        opts = Providers::ServerCreateOptions.new(
          name: name,
          type: server_type,
          image: image,
          location: location,
          user_data: user_data,
          network_id: network_id,
          firewall_id: firewall_id
        )

        server = @provider.create_server(opts)
        @log.info "Server created: %s (waiting for ready...)", server.id

        # Wait for server to be running
        server = @provider.wait_for_server(server.id, Constants::SERVER_READY_MAX_ATTEMPTS)
        @log.success "Server ready: %s (%s)", name, server.public_ipv4

        # Wait for SSH to be available
        wait_for_ssh(server.public_ipv4)

        server
      end

      private

      def generate_user_data
        ssh_key = @config.ssh_public_key

        <<~CLOUD_INIT
          #cloud-config
          users:
            - name: deploy
              groups: sudo, docker
              shell: /bin/bash
              sudo: ALL=(ALL) NOPASSWD:ALL
              ssh_authorized_keys:
                - #{ssh_key}
          package_update: true
          package_upgrade: true
          packages:
            - curl
            - git
            - jq
            - rsync
        CLOUD_INIT
      end

      def wait_for_ssh(ip)
        @log.info "Waiting for SSH on %s...", ip
        ssh = Remote::SSHExecutor.new(ip, @config.ssh_key_path)

        Constants::SSH_READY_MAX_ATTEMPTS.times do |i|
          begin
            output = ssh.execute("echo 'ready'")
            if output.strip == "ready"
              @log.success "SSH ready"
              return
            end
          rescue SSHCommandError
            # SSH not ready yet
          end

          sleep(Constants::SSH_READY_INTERVAL)
        end

        raise SSHConnectionError, "SSH connection failed after #{Constants::SSH_READY_MAX_ATTEMPTS} attempts"
      end
    end
  end
end
