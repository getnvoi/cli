# frozen_string_literal: true

module Nvoi
  class Cli
    module Deploy
      module Steps
        # ProvisionNetwork handles network and firewall provisioning
        class ProvisionNetwork
          def initialize(config, provider, log)
            @config = config
            @provider = provider
            @log = log
          end

          def run
            @log.info "Provisioning network infrastructure"

            network = provision_network
            firewall = provision_firewall

            @log.success "Network infrastructure ready"
            [network, firewall]
          end

          private

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
        end
      end
    end
  end
end
