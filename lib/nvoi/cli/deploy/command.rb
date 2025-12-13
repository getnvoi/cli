# frozen_string_literal: true

module Nvoi
  class Cli
    module Deploy
      # Command orchestrates the full deployment process
      class Command
        def initialize(options)
          @options = options
          @log = Nvoi.logger
        end

        def run
          @log.info "Deploy CLI %s", VERSION

          # Load configuration
          config_path = resolve_config_path
          working_dir = @options[:dir] || "."
          dockerfile_path = @options[:dockerfile_path] || File.join(working_dir, "Dockerfile")

          @config = Utils::ConfigLoader.load(config_path)

          # Apply branch override if specified
          apply_branch_override if @options[:branch]

          # Initialize cloud provider
          @provider = External::Cloud.for(@config)
          validate_provider_config

          @log.info "Using %s Cloud provider", @config.provider_name
          @log.info "Starting deployment"
          @log.separator

          # Step 1: Provision infrastructure (network, servers)
          main_server_ip = provision_infrastructure

          # Step 2: Configure Cloudflare tunnels
          tunnels = configure_tunnels

          # Step 3: Deploy application
          deploy_application(main_server_ip, tunnels, working_dir)

          # Success
          @log.separator
          @log.success "Deployment complete"

          # Log service URLs
          tunnels.each do |tunnel|
            @log.info "Service %s: https://%s", tunnel.service_name, tunnel.hostname
          end
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

          def validate_provider_config
            case @config.provider_name
            when "hetzner"
              h = @config.hetzner
              @provider.validate_credentials
              @provider.validate_instance_type(h.server_type)
              @provider.validate_region(h.server_location)
            when "aws"
              a = @config.aws
              @provider.validate_credentials
              @provider.validate_instance_type(a.instance_type)
              @provider.validate_region(a.region)
            when "scaleway"
              s = @config.scaleway
              @provider.validate_credentials
              @provider.validate_instance_type(s.server_type)
              @provider.validate_region(s.zone)
            end
          end

          def provision_infrastructure
            require_relative "steps/provision_network"
            require_relative "steps/provision_server"
            require_relative "steps/provision_volume"
            require_relative "steps/setup_k3s"

            # Step 1: Provision network and firewall
            network, firewall = Steps::ProvisionNetwork.new(@config, @provider, @log).run

            # Step 2: Provision servers
            main_server_ip = Steps::ProvisionServer.new(@config, @provider, @log, network, firewall).run

            # Step 3: Provision and mount volumes
            Steps::ProvisionVolume.new(@config, @provider, @log).run

            # Step 4: Setup K3s cluster
            Steps::SetupK3s.new(@config, @provider, @log, main_server_ip).run

            main_server_ip
          end

          def configure_tunnels
            require_relative "steps/configure_tunnel"
            Steps::ConfigureTunnel.new(@config, @log).run
          end

          def deploy_application(server_ip, tunnels, working_dir)
            require_relative "steps/build_image"
            require_relative "steps/deploy_service"
            require_relative "steps/cleanup_images"

            ssh = External::Ssh.new(server_ip, @config.ssh_key_path)
            registry_port = Utils::Constants::REGISTRY_PORT

            # Start SSH tunnel to registry
            registry_tunnel = External::SshTunnel.new(
              ip: server_ip,
              user: "deploy",
              key_path: @config.ssh_key_path,
              local_port: registry_port,
              remote_port: registry_port
            )

            registry_tunnel.start

            begin
              # Acquire deployment lock
              acquire_lock(ssh)

              begin
                # Build and push image via tunnel
                timestamp = Time.now.strftime("%Y%m%d%H%M%S")
                image_tag = @config.namer.image_tag(timestamp)

                registry_tag = Steps::BuildImage.new(@config, @log).run(working_dir, image_tag)

                # Deploy all services (image already in registry)
                Steps::DeployService.new(@config, ssh, tunnels, @log).run(registry_tag, timestamp)

                # Cleanup old images
                Steps::CleanupImages.new(@config, ssh, @log).run(timestamp)
              ensure
                release_lock(ssh)
              end
            ensure
              registry_tunnel.stop
            end
          end

          def acquire_lock(ssh)
            lock_file = @config.namer.deployment_lock_file_path

            output = ssh.execute("test -f #{lock_file} && cat #{lock_file} || echo ''")
            output = output.strip

            unless output.empty?
              timestamp = output.to_i
              if timestamp > 0
                lock_time = Time.at(timestamp)
                age = Time.now - lock_time

                if age < Utils::Constants::STALE_DEPLOYMENT_LOCK_AGE
                  raise Errors::DeploymentError.new(
                    "lock",
                    "deployment already in progress (started #{age.round}s ago). Wait or remove lock file: #{lock_file}"
                  )
                end

                @log.warning "Removing stale deployment lock (age: #{age.round}s)"
              end
            end

            ssh.execute("echo #{Time.now.to_i} > #{lock_file}")
            @log.info "Deployment lock acquired: %s", lock_file
          end

          def release_lock(ssh)
            lock_file = @config.namer.deployment_lock_file_path
            @log.info "Releasing deployment lock"
            ssh.execute("rm -f #{lock_file}")
          rescue StandardError
            # Ignore errors during lock release
          end
      end
    end
  end
end
