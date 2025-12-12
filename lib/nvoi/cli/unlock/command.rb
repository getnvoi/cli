# frozen_string_literal: true

module Nvoi
  class Cli
    module Unlock
      # Command removes deployment lock from remote server
      class Command
        def initialize(options)
          @options = options
          @log = Nvoi.logger
        end

        def run
          config_path = resolve_config_path
          @config = Utils::ConfigLoader.load(config_path)

          # Apply branch override if specified
          apply_branch_override if @options[:branch]

          # Initialize cloud provider
          @provider = External::Cloud.for(@config)

          # Find main server
          server = @provider.find_server(@config.server_name)
          raise Errors::ServiceError, "server not found: #{@config.server_name}" unless server

          ssh = External::Ssh.new(server.public_ipv4, @config.ssh_key_path)
          lock_file = @config.namer.deployment_lock_file_path

          # Check if lock exists and show info
          output = ssh.execute("test -f #{lock_file} && cat #{lock_file} || echo ''").strip

          if output.empty?
            @log.info "No lock file found: %s", lock_file
            return
          end

          timestamp = output.to_i
          if timestamp > 0
            lock_time = Time.at(timestamp)
            age = Time.now - lock_time
            @log.info "Lock file age: %ds (since %s)", age.round, lock_time.strftime("%H:%M:%S")
          end

          ssh.execute("rm -f #{lock_file}")
          @log.success "Removed lock file: %s", lock_file
        end

        private

          def resolve_config_path
            config_path = @options[:config] || "deploy.enc"
            working_dir = @options[:dir]

            if config_path == "deploy.enc" && working_dir && working_dir != "."
              File.join(working_dir, "deploy.enc")
            else
              config_path
            end
          end

          def apply_branch_override
            branch = @options[:branch]
            return if branch.nil? || branch.empty?

            override = Objects::ConfigOverride.new(branch:)
            override.apply(@config)
          end
      end
    end
  end
end
