# frozen_string_literal: true

module Nvoi
  class Cli
    module Delete
      module Steps
        # TeardownFirewall handles firewall deletion
        class TeardownFirewall
          def initialize(config, provider, log)
            @config = config
            @provider = provider
            @log = log
          end

          def run
            @log.info "Deleting firewall: %s", @config.firewall_name

            firewall = @provider.get_firewall_by_name(@config.firewall_name)
            delete_firewall_with_retry(firewall.id) if firewall
          rescue FirewallError => e
            @log.warning "Firewall not found: %s", e.message
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
        end
      end
    end
  end
end
