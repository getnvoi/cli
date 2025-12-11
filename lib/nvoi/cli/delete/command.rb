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

          # Detach volumes first (must happen before server deletion)
          detach_volumes

          # Delete all servers
          delete_all_servers

          # Delete volumes
          delete_volumes

          # Delete firewall
          delete_firewall

          # Delete network
          delete_network

          # Delete Cloudflare resources
          delete_cloudflare_resources

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

          def detach_volumes
            volume_names = collect_volume_names
            return if volume_names.empty?

            @log.info "Detaching %d volume(s)", volume_names.size

            volume_names.each do |vol_name|
              begin
                volume = @provider.get_volume_by_name(vol_name)
                next unless volume&.server_id && !volume.server_id.empty?

                @log.info "Detaching volume: %s", vol_name
                @provider.detach_volume(volume.id)
                @log.success "Volume detached: %s", vol_name
              rescue StandardError => e
                @log.warning "Failed to detach volume %s: %s", vol_name, e.message
              end
            end
          end

          def delete_all_servers
            servers = @config.deploy.application.servers
            return if servers.empty?

            servers.each do |group_name, group_config|
              next unless group_config

              count = group_config.count.positive? ? group_config.count : 1
              @log.info "Deleting %d server(s) from group '%s'", count, group_name

              (1..count).each do |i|
                server_name = @config.namer.server_name(group_name, i)
                @log.info "Deleting server: %s", server_name

                begin
                  server = @provider.find_server(server_name)
                  if server
                    @provider.delete_server(server.id)
                    @log.success "Server deleted: %s", server_name
                  end
                rescue StandardError => e
                  @log.warning "Failed to delete server %s: %s", server_name, e.message
                end
              end
            end
          end

          def delete_volumes
            volume_names = collect_volume_names
            return if volume_names.empty?

            @log.info "Deleting %d volume(s)", volume_names.size

            volume_names.each do |vol_name|
              @log.info "Deleting volume: %s", vol_name

              begin
                volume = @provider.get_volume_by_name(vol_name)
                unless volume
                  @log.info "Volume not found: %s", vol_name
                  next
                end

                @provider.delete_volume(volume.id)
                @log.success "Volume deleted: %s", vol_name
              rescue StandardError => e
                @log.warning "Failed to delete volume %s: %s", vol_name, e.message
              end
            end
          end

          def collect_volume_names
            namer = @config.namer
            names = []

            @config.deploy.application.servers.each do |server_name, server_config|
              next unless server_config.volumes && !server_config.volumes.empty?

              server_config.volumes.each_key do |vol_name|
                names << namer.server_volume_name(server_name, vol_name)
              end
            end

            names
          end

          def delete_firewall
            @log.info "Deleting firewall: %s", @config.firewall_name

            begin
              firewall = @provider.get_firewall_by_name(@config.firewall_name)
              delete_firewall_with_retry(firewall.id) if firewall
            rescue FirewallError => e
              @log.warning "Firewall not found: %s", e.message
            end
          end

          def delete_firewall_with_retry(firewall_id, max_retries: 5)
            max_retries.times do |i|
              begin
                @provider.delete_firewall(firewall_id)
                @log.success "Firewall deleted"
                return
              rescue StandardError => e
                if i == max_retries - 1
                  raise ServiceError, "failed to delete firewall after #{max_retries} attempts: #{e.message}"
                end

                @log.info "Firewall still in use, waiting 3s before retry (%d/%d)", i + 1, max_retries
                sleep(3)
              end
            end
          end

          def delete_network
            @log.info "Deleting network: %s", @config.network_name

            begin
              network = @provider.get_network_by_name(@config.network_name)
              if network
                @provider.delete_network(network.id)
                @log.success "Network deleted"
              end
            rescue NetworkError => e
              @log.warning "Network not found: %s", e.message
            end
          end

          def delete_cloudflare_resources
            @config.deploy.application.app.each do |service_name, service|
              next unless service&.domain && !service.domain.empty?
              next if service.subdomain.nil?

              delete_tunnel_and_dns(service_name, service.domain, service.subdomain)
            end
          end

          def delete_tunnel_and_dns(service_name, domain, subdomain)
            tunnel_name = @config.namer.tunnel_name(service_name)
            hostname = Utils::Namer.build_hostname(subdomain, domain)

            # Delete tunnel
            @log.info "Deleting Cloudflare tunnel: %s", tunnel_name
            begin
              tunnel = @cf_client.find_tunnel(tunnel_name)
              if tunnel
                @cf_client.delete_tunnel(tunnel.id)
                @log.success "Tunnel deleted: %s", tunnel_name
              end
            rescue StandardError => e
              @log.warning "Failed to delete tunnel: %s", e.message
            end

            # Delete DNS record
            @log.info "Deleting DNS record: %s", hostname
            begin
              zone = @cf_client.find_zone(domain)
              unless zone
                @log.warning "Zone not found: %s", domain
                return
              end

              record = @cf_client.find_dns_record(zone.id, hostname, "CNAME")
              if record
                @cf_client.delete_dns_record(zone.id, record.id)
                @log.success "DNS record deleted: %s", hostname
              end
            rescue StandardError => e
              @log.warning "Failed to delete DNS record: %s", e.message
            end
          end
      end
    end
  end
end
