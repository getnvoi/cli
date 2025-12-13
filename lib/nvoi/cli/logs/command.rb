# frozen_string_literal: true

module Nvoi
  class Cli
    module Logs
      # Command streams logs from app pods
      class Command
        def initialize(options)
          @options = options
          @log = Nvoi.logger
        end

        def run(app_name)
          config_path = resolve_config_path
          @config = Utils::ConfigLoader.load(config_path)

          # Apply branch override if specified
          apply_branch_override if @options[:branch]

          # Initialize cloud provider
          @provider = External::Cloud.for(@config)

          # Find main server
          server = @provider.find_server(@config.server_name)
          raise Errors::ServiceError, "server not found: #{@config.server_name}" unless server

          # Build deployment name from app name
          deployment_name = @config.namer.app_deployment_name(app_name)

          # Build kubectl logs command
          # --prefix shows pod name, --all-containers handles multi-container pods
          follow_flag = @options[:follow] ? "-f" : ""
          tail_flag = "--tail=#{@options[:tail]}"

          kubectl_cmd = "kubectl logs -l app=#{deployment_name} --prefix --all-containers #{follow_flag} #{tail_flag}".strip.squeeze(" ")

          @log.info "Streaming logs for %s", deployment_name

          ssh = External::Ssh.new(server.public_ipv4, @config.ssh_key_path)
          ssh.execute(kubectl_cmd, stream: true)
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
            return if branch.blank?

            override = Configuration::Override.new(branch:)
            override.apply(@config)
          end
      end
    end
  end
end
