# frozen_string_literal: true

module Nvoi
  module Steps
    # TunnelConfigurator handles Cloudflare tunnel setup for services
    class TunnelConfigurator
      def initialize(config, log)
        @config = config
        @log = log

        cf = config.cloudflare
        @cf_client = Cloudflare::Client.new(cf.api_token, cf.account_id)
        @tunnel_manager = Deployer::TunnelManager.new(@cf_client, log)
      end

      def run
        @log.info "Configuring Cloudflare tunnels"

        tunnels = []

        @config.deploy.application.app.each do |service_name, service_config|
          next unless service_config.domain && !service_config.domain.empty?
          next unless service_config.port && service_config.port.positive?
          # Allow empty subdomain or "@" for apex domain
          next if service_config.subdomain.nil?

          tunnel_info = configure_service_tunnel(service_name, service_config)
          tunnels << tunnel_info
        end

        @log.success "All tunnels configured (%d)", tunnels.size
        tunnels
      end

      private

        def configure_service_tunnel(service_name, service_config)
          tunnel_name = @config.namer.tunnel_name(service_name)
          hostname = build_hostname(service_config.subdomain, service_config.domain)

          # Service URL points to the K8s service
          k8s_service_name = @config.namer.app_service_name(service_name)
          service_url = "http://#{k8s_service_name}:#{service_config.port}"

          tunnel = @tunnel_manager.setup_tunnel(tunnel_name, hostname, service_url, service_config.domain)

          Deployer::TunnelInfo.new(
            service_name:,
            hostname:,
            tunnel_id: tunnel.tunnel_id,
            tunnel_token: tunnel.tunnel_token
          )
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
