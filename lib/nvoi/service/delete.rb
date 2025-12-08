# frozen_string_literal: true

module Nvoi
  module Service
    # DeleteService handles cleanup of cloud resources
    class DeleteService
      include ProviderHelper

      attr_accessor :config_dir

      def initialize(config_path, log)
        @log = log

        # Load configuration
        @config = Config.load(config_path)

        # Initialize provider
        @provider = init_provider(@config)

        # Initialize Cloudflare client
        cf = @config.cloudflare
        @cf_client = Cloudflare::Client.new(cf.api_token, cf.account_id)
      end

      def run
        @log.info "Using %s Cloud provider", @config.provider_name

        # Detach volumes first (must happen before server deletion)
        detach_volumes

        # Delete all servers from all groups
        delete_all_servers

        # Delete volumes (already detached)
        delete_volumes

        # Delete firewall
        @log.info "Deleting firewall: %s", @config.firewall_name
        begin
          firewall = @provider.get_firewall_by_name(@config.firewall_name)
          delete_firewall_with_retry(firewall.id) if firewall
        rescue FirewallError => e
          @log.warning "Firewall not found: %s", e.message
        end

        # Delete network
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

        # Delete Cloudflare resources
        delete_cloudflare_resources

        @log.success "Cleanup complete"
      end

      private

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

        # Database volume
        db = @config.deploy.application.database
        names << namer.database_volume_name if db&.volume && !db.volume.empty?

        # Service volumes
        @config.deploy.application.services.each do |svc_name, svc|
          names << namer.service_volume_name(svc_name, "data") if svc&.volume && !svc.volume.empty?
        end

        # App volumes
        @config.deploy.application.app.each do |app_name, app|
          next unless app&.volumes && !app.volumes.empty?

          app.volumes.keys.each do |vol_key|
            names << namer.app_volume_name(app_name, vol_key)
          end
        end

        names
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

      def delete_cloudflare_resources
        @config.deploy.application.app.each do |service_name, service|
          next unless service&.domain && !service.domain.empty?
          next if service.subdomain.nil?

          delete_tunnel_and_dns(service_name, service.domain, service.subdomain)
        end
      end

      def delete_tunnel_and_dns(service_name, domain, subdomain)
        tunnel_name = @config.namer.tunnel_name(service_name)
        hostname = build_hostname(subdomain, domain)

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

      # Build hostname from subdomain and domain
      # Supports: "app" -> "app.example.com", "" or "@" -> "example.com", "*" -> "*.example.com"
      def build_hostname(subdomain, domain)
        if subdomain.nil? || subdomain.empty? || subdomain == "@"
          domain
        else
          "#{subdomain}.#{domain}"
        end
      end
    end
  end
end
