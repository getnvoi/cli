# frozen_string_literal: true

module Nvoi
  class Cli
    module Delete
      module Steps
        # TeardownTunnel handles Cloudflare tunnel deletion
        class TeardownTunnel
          def initialize(config, cf_client, log)
            @config = config
            @cf_client = cf_client
            @log = log
            @namer = config.namer
          end

          def run
            @config.deploy.application.app.each do |service_name, service|
              next unless service&.domain && !service.domain.empty?
              next if service.subdomain.nil?

              delete_tunnel(service_name)
            end
          end

          private

            def delete_tunnel(service_name)
              tunnel_name = @namer.tunnel_name(service_name)

              @log.info "Deleting Cloudflare tunnel: %s", tunnel_name

              tunnel = @cf_client.find_tunnel(tunnel_name)
              if tunnel
                @cf_client.delete_tunnel(tunnel.id)
                @log.success "Tunnel deleted: %s", tunnel_name
              end
            rescue StandardError => e
              @log.warning "Failed to delete tunnel: %s", e.message
            end
        end
      end
    end
  end
end
