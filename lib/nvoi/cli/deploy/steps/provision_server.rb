# frozen_string_literal: true

module Nvoi
  class Cli
    module Deploy
      module Steps
        # ProvisionServer handles compute server provisioning
        class ProvisionServer
          def initialize(config, provider, log, network, firewall)
            @config = config
            @provider = provider
            @log = log
            @network = network
            @firewall = firewall
          end

          def run
            @log.info "Provisioning servers"

            servers = @config.deploy.application.servers
            main_server_ip = nil

            servers.each do |group_name, group_config|
              count = group_config&.count&.positive? ? group_config.count : 1

              (1..count).each do |i|
                server_name = @config.namer.server_name(group_name, i)
                server = provision_server(server_name, group_config)

                # Track main server IP (first master, or just first server)
                main_server_ip ||= server.public_ipv4 if group_config&.master || i == 1
              end
            end

            @log.success "All servers provisioned"
            main_server_ip
          end

          private

            def provision_server(name, server_config)
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
              image = "ubuntu-22.04"

              case @config.provider_name
              when "hetzner"
                h = @config.hetzner
                server_type ||= h.server_type
                location ||= h.server_location
              when "aws"
                a = @config.aws
                server_type ||= a.instance_type
                location ||= a.region
              when "scaleway"
                s = @config.scaleway
                server_type ||= s.server_type
                location ||= s.zone
              end

              # Create cloud-init user data
              user_data = generate_user_data

              opts = Objects::Server::CreateOptions.new(
                name:,
                type: server_type,
                image:,
                location:,
                user_data:,
                network_id: @network.id,
                firewall_id: @firewall.id
              )

              server = @provider.create_server(opts)
              @log.info "Server created: %s (waiting for ready...)", server.id

              # Wait for server to be running
              server = @provider.wait_for_server(server.id, Utils::Constants::SERVER_READY_MAX_ATTEMPTS)
              @log.success "Server ready: %s (%s)", name, server.public_ipv4

              # Wait for SSH to be available
              wait_for_ssh(server.public_ipv4)

              server
            end

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
              ssh = External::Ssh.new(ip, @config.ssh_key_path)

              Utils::Constants::SSH_READY_MAX_ATTEMPTS.times do |_i|
                begin
                  output = ssh.execute("echo 'ready'")
                  if output.strip == "ready"
                    @log.success "SSH ready"
                    return
                  end
                rescue SshCommandError
                  # SSH not ready yet
                end

                sleep(Utils::Constants::SSH_READY_INTERVAL)
              end

              raise Errors::SshConnectionError, "SSH connection failed after #{Utils::Constants::SSH_READY_MAX_ATTEMPTS} attempts"
            end
        end
      end
    end
  end
end
