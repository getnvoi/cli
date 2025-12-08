# frozen_string_literal: true

module Nvoi
  module Deployer
    # TunnelManager handles Cloudflare tunnel operations
    class TunnelManager
      def initialize(cf_client, log)
        @cf_client = cf_client
        @log = log
      end

      # Create or get existing tunnel, configure it, and create DNS record
      def setup_tunnel(tunnel_name, hostname, service_url, domain)
        @log.info "Setting up tunnel: %s -> %s", tunnel_name, hostname

        # Find or create tunnel
        tunnel = @cf_client.find_tunnel(tunnel_name)

        if tunnel
          @log.info "Using existing tunnel: %s", tunnel_name
        else
          @log.info "Creating new tunnel: %s", tunnel_name
          tunnel = @cf_client.create_tunnel(tunnel_name)
        end

        # Get tunnel token
        token = tunnel.token
        if token.nil? || token.empty?
          token = @cf_client.get_tunnel_token(tunnel.id)
        end

        # Configure tunnel ingress
        @log.info "Configuring tunnel ingress: %s -> %s", hostname, service_url
        @cf_client.update_tunnel_configuration(tunnel.id, hostname, service_url)

        # Verify configuration propagated
        @log.info "Verifying tunnel configuration..."
        @cf_client.verify_tunnel_configuration(tunnel.id, hostname, service_url, Constants::TUNNEL_CONFIG_VERIFY_ATTEMPTS)

        # Create DNS record
        @log.info "Creating DNS CNAME record: %s", hostname
        zone = @cf_client.find_zone(domain)
        raise CloudflareError, "zone not found: #{domain}" unless zone

        tunnel_cname = "#{tunnel.id}.cfargotunnel.com"
        @cf_client.create_or_update_dns_record(zone.id, hostname, "CNAME", tunnel_cname, proxied: true)

        @log.success "Tunnel configured: %s", tunnel_name

        TunnelInfo.new(
          tunnel_id: tunnel.id,
          tunnel_token: token
        )
      end
    end
  end
end
