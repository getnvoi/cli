# frozen_string_literal: true

module Nvoi
  class Cli
    module Delete
      module Steps
        # TeardownDns handles DNS record deletion
        class TeardownDns
          def initialize(config, cf_client, log)
            @config = config
            @cf_client = cf_client
            @log = log
          end

          def run
            @config.deploy.application.app.each do |_service_name, service|
              next unless service&.domain && !service.domain.empty?

              delete_dns_records(service.domain, service.subdomain)
            end
          end

          private

            def delete_dns_records(domain, subdomain)
              hostnames = Utils::Namer.build_hostnames(subdomain, domain)

              zone = @cf_client.find_zone(domain)
              unless zone
                @log.warning "Zone not found: %s", domain
                return
              end

              hostnames.each do |hostname|
                @log.info "Deleting DNS record: %s", hostname

                record = @cf_client.find_dns_record(zone.id, hostname, "CNAME")
                if record
                  @cf_client.delete_dns_record(zone.id, record.id)
                  @log.success "DNS record deleted: %s", hostname
                end
              end
            rescue StandardError => e
              @log.warning "Failed to delete DNS records: %s", e.message
            end
        end
      end
    end
  end
end
