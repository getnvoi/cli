# frozen_string_literal: true

module Nvoi
  module Steps
    # ServicesProvisioner handles deployment of additional services (redis, etc.)
    class ServicesProvisioner
      def initialize(config, ssh, log)
        @config = config
        @ssh = ssh
        @log = log
        @service_deployer = Deployer::ServiceDeployer.new(config, ssh, log)
      end

      def run
        services = @config.deploy.application.services
        return if services.empty?

        @log.info "Provisioning %d additional service(s)", services.size

        services.each do |service_name, service_config|
          service_spec = service_config.to_service_spec(@config.deploy.application.name, service_name)
          @service_deployer.deploy_service(service_name, service_spec)
        end

        @log.success "Additional services provisioned"
      end
    end
  end
end
