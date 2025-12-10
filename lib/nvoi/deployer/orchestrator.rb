# frozen_string_literal: true

module Nvoi
  module Deployer
    # Orchestrator coordinates the deployment pipeline
    class Orchestrator
      def initialize(config, provider, log)
        @config = config
        @provider = provider
        @log = log
      end

      def run(server_ip, tunnels, working_dir)
        @log.info "Starting deployment orchestration"

        # Create SSH connection to main server
        @ssh = Remote::SSHExecutor.new(server_ip, @config.ssh_key_path)

        # Acquire deployment lock
        acquire_lock

        begin
          run_deployment(tunnels, working_dir)
        ensure
          release_lock
        end
      end

      private

        def run_deployment(tunnels, working_dir)
          ssh = @ssh
          docker = Remote::DockerManager.new(ssh)

          # Generate image tag
          timestamp = Time.now.strftime("%Y%m%d%H%M%S")
          image_tag = @config.namer.image_tag(timestamp)

          # Build and push image
          image_builder = ImageBuilder.new(@config, docker, @log)
          image_builder.build_and_push(working_dir, image_tag)

          # Tag as latest locally for K8s to use
          # The image is already in containerd from build_image
          registry_tag = "localhost:#{Constants::REGISTRY_PORT}/#{@config.container_prefix}:#{timestamp}"
          push_to_registry(ssh, image_tag, registry_tag)

          # Deploy services
          service_deployer = ServiceDeployer.new(@config, ssh, @log)

          # Gather all env vars using EnvResolver (single source of truth)
          # Use first app service to get full env (includes database vars, deploy_env, etc.)
          first_service = @config.deploy.application.app.keys.first
          all_env = @config.env_for_service(first_service)

          # Deploy app secret
          service_deployer.deploy_app_secret(all_env)

          # Deploy database if configured (to_service_spec returns nil for sqlite3)
          db_config = @config.deploy.application.database
          if db_config
            db_spec = db_config.to_service_spec(@config.namer)
            service_deployer.deploy_database(db_spec) if db_spec
          end

          # Deploy additional services
          @config.deploy.application.services.each do |service_name, service_config|
            service_spec = service_config.to_service_spec(@config.deploy.application.name, service_name)
            service_deployer.deploy_service(service_name, service_spec)
          end

          # Deploy app services
          @config.deploy.application.app.each do |service_name, service_config|
            service_env = @config.env_for_service(service_name)
            service_deployer.deploy_app_service(service_name, service_config, registry_tag, service_env)

            # Deploy cloudflared for services with tunnels
            tunnel = tunnels.find { |t| t.service_name == service_name }
            if tunnel
              service_deployer.deploy_cloudflared(service_name, tunnel.tunnel_token)

              # Verify traffic is routing correctly
              service_deployer.verify_traffic_switchover(service_config)
            end
          end

          # Cleanup old images
          cleaner = Cleaner.new(@config, docker, @log)
          cleaner.cleanup_old_images(timestamp)

          @log.success "Deployment orchestration complete"
        end

        def acquire_lock
          lock_file = @config.namer.deployment_lock_file_path

          # Check if lock file exists
          output = @ssh.execute("test -f #{lock_file} && cat #{lock_file} || echo ''")
          output = output.strip

          unless output.empty?
            # Lock exists, check timestamp
            timestamp = output.to_i
            if timestamp > 0
              lock_time = Time.at(timestamp)
              age = Time.now - lock_time

              if age < Constants::STALE_DEPLOYMENT_LOCK_AGE
                raise DeploymentError.new(
                  "lock",
                  "deployment already in progress (started #{age.round}s ago). Wait or remove lock file: #{lock_file}"
                )
              end

              # Lock is stale, will overwrite
              @log.warning "Removing stale deployment lock (age: #{age.round}s)"
            end
          end

          # Create lock file with current timestamp
          @ssh.execute("echo #{Time.now.to_i} > #{lock_file}")
          @log.info "Deployment lock acquired: %s", lock_file
        end

        def release_lock
          lock_file = @config.namer.deployment_lock_file_path
          @log.info "Releasing deployment lock"
          @ssh.execute("rm -f #{lock_file}")
        rescue StandardError
          # Ignore errors during lock release
        end

        def push_to_registry(ssh, local_tag, registry_tag)
          @log.info "Pushing to in-cluster registry: %s", registry_tag

          # Tag for registry
          ssh.execute("sudo ctr -n k8s.io images tag #{local_tag} #{registry_tag}")

          # Push to local registry
          ssh.execute("sudo ctr -n k8s.io images push --plain-http #{registry_tag}")

          @log.success "Image pushed to registry"
        end
    end
  end
end
