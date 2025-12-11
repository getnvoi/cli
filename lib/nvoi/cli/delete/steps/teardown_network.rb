# frozen_string_literal: true

module Nvoi
  class Cli
    module Delete
      module Steps
        # TeardownNetwork handles network deletion
        class TeardownNetwork
          def initialize(config, provider, log)
            @config = config
            @provider = provider
            @log = log
          end

          def run
            @log.info "Deleting network: %s", @config.network_name

            network = @provider.get_network_by_name(@config.network_name)
            if network
              @provider.delete_network(network.id)
              @log.success "Network deleted"
            end
          rescue NetworkError => e
            @log.warning "Network not found: %s", e.message
          end
        end
      end
    end
  end
end
