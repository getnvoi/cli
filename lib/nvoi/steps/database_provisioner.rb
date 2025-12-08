# frozen_string_literal: true

module Nvoi
  module Steps
    # DatabaseProvisioner handles database deployment
    class DatabaseProvisioner
      def initialize(config, ssh, log)
        @config = config
        @ssh = ssh
        @log = log
        @service_deployer = Deployer::ServiceDeployer.new(config, ssh, log)
      end

      def run
        db_config = @config.deploy.application.database
        return unless db_config

        # SQLite is handled by app deployment with PVC volumes
        if db_config.adapter == "sqlite3"
          @log.info "SQLite database will be provisioned with app deployment"
          return
        end

        @log.info "Provisioning %s database via K8s", db_config.adapter

        db_spec = db_config.to_service_spec(@config.namer)
        @service_deployer.deploy_database(db_spec)

        # Wait for database to be ready
        wait_for_database(db_spec.name)

        @log.success "Database provisioned"
      end

      private

      def wait_for_database(name, timeout: 120)
        @log.info "Waiting for database to be ready..."

        start_time = Time.now
        loop do
          begin
            output = @ssh.execute("kubectl get pods -l app=#{name} -o jsonpath='{.items[0].status.phase}'")
            if output.strip == "Running"
              @log.success "Database is running"
              return
            end
          rescue SSHCommandError
            # Not ready yet
          end

          elapsed = Time.now - start_time
          raise K8sError, "database failed to start within #{timeout}s" if elapsed > timeout

          sleep(5)
        end
      end
    end
  end
end
