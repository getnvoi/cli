# frozen_string_literal: true

module Nvoi
  class Cli
    module Deploy
      module Steps
        # ConfigureTunnel handles Cloudflare tunnel setup for services
        class ConfigureTunnel
          def initialize(config, log)
            @config = config
            @log = log

            cf = config.cloudflare
            @cf_client = External::Dns::Cloudflare.new(cf.api_token, cf.account_id)
          end

          def run
            @log.info "Configuring Cloudflare tunnels"

            tunnels = []

            @config.deploy.application.app.each do |service_name, service_config|
              next unless service_config.domain && !service_config.domain.empty?
              next unless service_config.port && service_config.port.positive?

              tunnel_info = configure_service_tunnel(service_name, service_config)
              tunnels << tunnel_info
            end

            @log.success "All tunnels configured (%d)", tunnels.size
            tunnels
          end

          private

            def configure_service_tunnel(service_name, service_config)
              tunnel_name = @config.namer.tunnel_name(service_name)
              hostnames = Utils::Namer.build_hostnames(service_config.subdomain, service_config.domain)
              primary_hostname = hostnames.first

              # Service URL points to the NGINX Ingress Controller
              service_url = "http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80"

              tunnel = setup_tunnel(tunnel_name, hostnames, service_url, service_config.domain)

              External::Dns::Types::Tunnel::Info.new(
                service_name:,
                hostname: primary_hostname,
                tunnel_id: tunnel.tunnel_id,
                tunnel_token: tunnel.tunnel_token
              )
            end

            def setup_tunnel(tunnel_name, hostnames, service_url, domain)
              @log.info "Setting up tunnel: %s -> %s", tunnel_name, hostnames.join(", ")

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

              # Configure tunnel ingress for all hostnames
              @log.info "Configuring tunnel ingress: %s -> %s", hostnames.join(", "), service_url
              @cf_client.update_tunnel_configuration(tunnel.id, hostnames, service_url)

              # Verify configuration propagated
              @log.info "Verifying tunnel configuration..."
              @cf_client.verify_tunnel_configuration(tunnel.id, hostnames, service_url, Utils::Constants::TUNNEL_CONFIG_VERIFY_ATTEMPTS)

              # Create DNS records for all hostnames
              zone = @cf_client.find_zone(domain)
              raise Errors::CloudflareError, "zone not found: #{domain}" unless zone

              tunnel_cname = "#{tunnel.id}.cfargotunnel.com"
              hostnames.each do |hostname|
                @log.info "Creating DNS CNAME record: %s", hostname
                @cf_client.create_or_update_dns_record(zone.id, hostname, "CNAME", tunnel_cname, proxied: true)
              end

              @log.success "Tunnel configured: %s", tunnel_name

              External::Dns::Types::Tunnel::Info.new(
                tunnel_id: tunnel.id,
                tunnel_token: token
              )
            end
        end
      end
    end
  end
end
