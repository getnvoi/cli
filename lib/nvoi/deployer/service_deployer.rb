# frozen_string_literal: true

module Nvoi
  module Deployer
    # ServiceDeployer handles K8s deployment of application services
    class ServiceDeployer
      DEFAULT_RESOURCES = {
        request_memory: "128Mi",
        request_cpu: "100m",
        limit_memory: "512Mi",
        limit_cpu: "500m"
      }.freeze

      def initialize(config, ssh, log)
        @config = config
        @ssh = ssh
        @log = log
        @namer = config.namer
      end

      # Deploy app secret with environment variables
      def deploy_app_secret(env_vars)
        secret_name = @namer.app_secret_name

        @log.info "Deploying app secret: %s", secret_name

        K8s::Renderer.apply_manifest(@ssh, "app-secret.yaml", {
          name: secret_name,
          env_vars:
        })

        @log.success "App secret deployed"
      end

      # Deploy an app service (web, worker, etc.)
      def deploy_app_service(service_name, service_config, image_tag, env)
        deployment_name = @namer.app_deployment_name(service_name)
        @log.info "Deploying app service: %s", deployment_name

        # Determine template based on port
        has_port = service_config.port && service_config.port.positive?
        template = has_port ? "app-deployment.yaml" : "worker-deployment.yaml"

        # Build readiness probe if healthcheck configured
        readiness_probe = nil
        liveness_probe = nil

        if service_config.healthcheck && has_port
          hc = service_config.healthcheck
          readiness_probe = {
            path: hc.path || "/health",
            port: hc.port || service_config.port,
            initial_delay: 10,
            period: 10,
            timeout: 5,
            failure_threshold: 3
          }
          liveness_probe = readiness_probe.merge(initial_delay: 30)
        end

        data = {
          name: deployment_name,
          image: image_tag,
          replicas: has_port ? 2 : 1,
          port: service_config.port,
          command: service_config.command&.split || [],
          secret_name: @namer.app_secret_name,
          env_keys: env.keys.sort,
          affinity_server_names: service_config.servers,
          resources: DEFAULT_RESOURCES,
          readiness_probe:,
          liveness_probe:,
          volume_mounts: [],
          host_path_volumes: [],
          volumes: []
        }

        # Add mounts if configured (volumes are now server-level)
        if service_config.mounts && !service_config.mounts.empty?
          # Validate: single server only for services with mounts
          if service_config.servers.length > 1
            raise DeploymentError.new(
              "validation",
              "app '#{service_name}' runs on multiple servers #{service_config.servers} " \
              "and cannot have mounts. Volumes are server-local and would cause data inconsistency."
            )
          end

          server_name = service_config.servers.first
          server_config = @config.deploy.application.servers[server_name]

          service_config.mounts.each do |vol_name, mount_path|
            # Validate: volume exists on the server
            unless server_config&.volumes&.key?(vol_name)
              available = server_config&.volumes&.keys&.join(", ") || "none"
              raise DeploymentError.new(
                "validation",
                "app '#{service_name}' mounts '#{vol_name}' but server '#{server_name}' " \
                "has no volume named '#{vol_name}'. Available: #{available}"
              )
            end

            host_path = @namer.server_volume_host_path(server_name, vol_name)
            data[:volume_mounts] << { name: vol_name, mount_path: }
            data[:host_path_volumes] << { name: vol_name, host_path: }
          end
        end

        K8s::Renderer.apply_manifest(@ssh, template, data)

        # Deploy service if it has a port
        if has_port
          K8s::Renderer.apply_manifest(@ssh, "app-service.yaml", {
            name: deployment_name,
            port: service_config.port
          })
        end

        # Deploy ingress if domain is specified
        if service_config.domain && !service_config.domain.empty?
          hostname = if service_config.subdomain && !service_config.subdomain.empty? && service_config.subdomain != "@"
            "#{service_config.subdomain}.#{service_config.domain}"
          else
            service_config.domain
          end

          K8s::Renderer.apply_manifest(@ssh, "app-ingress.yaml", {
            name: deployment_name,
            domain: hostname,
            port: service_config.port
          })
        end

        # Wait for deployment to be ready
        @log.info "Waiting for deployment to be ready..."
        K8s::Renderer.wait_for_deployment(@ssh, deployment_name)

        # Run pre-run command if specified (e.g., rails db:migrate)
        if service_config.pre_run_command && !service_config.pre_run_command.empty?
          run_pre_run_command(service_name, service_config.pre_run_command)
        end

        @log.success "App service deployed: %s", deployment_name
      end

      # Deploy database as StatefulSet
      def deploy_database(db_spec)
        @log.info "Deploying database: %s", db_spec.name

        data = {
          service_name: db_spec.name,
          adapter: @config.deploy.application.database.adapter,
          image: db_spec.image,
          port: db_spec.port,
          secret_name: @namer.database_secret_name,
          secret_keys: db_spec.secrets.keys.sort,
          data_path: "/var/lib/postgresql/data",
          storage_size: "10Gi",
          affinity_server_names: db_spec.servers,
          host_path: nil
        }

        # Use hostPath for database volume if configured (mounts reference server volumes)
        db_mount = @config.deploy.application.database.mount
        if db_mount && !db_mount.empty?
          server_name = db_spec.servers.first
          vol_name = db_mount.keys.first
          data[:host_path] = @namer.server_volume_host_path(server_name, vol_name)
        end

        # Create database secret first
        K8s::Renderer.apply_manifest(@ssh, "app-secret.yaml", {
          name: @namer.database_secret_name,
          env_vars: db_spec.secrets
        })

        # Deploy StatefulSet
        K8s::Renderer.apply_manifest(@ssh, "db-statefulset.yaml", data)

        # Wait for database to be ready
        @log.info "Waiting for database to be ready..."
        wait_for_statefulset(db_spec.name)

        @log.success "Database deployed: %s", db_spec.name
      end

      # Deploy additional service (redis, etc.)
      def deploy_service(service_name, service_spec)
        @log.info "Deploying service: %s", service_spec.name

        host_path = nil
        volume_path = nil
        if service_spec.mounts && !service_spec.mounts.empty?
          server_name = service_spec.servers.first
          vol_name, mount_path = service_spec.mounts.first
          host_path = @namer.server_volume_host_path(server_name, vol_name)
          volume_path = mount_path
        end

        data = {
          name: service_spec.name,
          image: service_spec.image,
          port: service_spec.port,
          command: service_spec.command,
          env_vars: service_spec.env,
          env_keys: service_spec.env.keys.sort,
          volume_path:,
          host_path:,
          affinity_server_names: service_spec.servers
        }

        K8s::Renderer.apply_manifest(@ssh, "service-deployment.yaml", data)

        @log.success "Service deployed: %s", service_spec.name
      end

      # Deploy cloudflared sidecar
      def deploy_cloudflared(service_name, tunnel_token)
        deployment_name = @namer.cloudflared_deployment_name(service_name)
        @log.info "Deploying cloudflared: %s", deployment_name

        # Simple cloudflared deployment
        manifest = <<~YAML
          apiVersion: apps/v1
          kind: Deployment
          metadata:
            name: #{deployment_name}
            namespace: default
          spec:
            replicas: 1
            selector:
              matchLabels:
                app: #{deployment_name}
            template:
              metadata:
                labels:
                  app: #{deployment_name}
              spec:
                containers:
                - name: cloudflared
                  image: cloudflare/cloudflared:latest
                  args:
                  - tunnel
                  - run
                  - --token
                  - #{tunnel_token}
        YAML

        @ssh.execute("cat <<'EOF' | kubectl apply -f -\n#{manifest}\nEOF")

        @log.success "Cloudflared deployed: %s", deployment_name
      end

      # Verify traffic is routing to the new deployment via public URL
      # Checks both HTTP status (200) and absence of X-Nvoi-Error header
      # (which indicates the error backend is serving, meaning the real app is down)
      def verify_traffic_switchover(service_config)
        return unless service_config.domain && !service_config.domain.empty?

        hostname = if service_config.subdomain && !service_config.subdomain.empty? && service_config.subdomain != "@"
          "#{service_config.subdomain}.#{service_config.domain}"
        else
          service_config.domain
        end

        health_path = service_config.healthcheck&.path || "/"
        public_url = "https://#{hostname}#{health_path}"

        @log.info "Verifying public traffic routing"
        @log.info "Testing: %s", public_url

        consecutive_success = 0
        required_consecutive = Constants::TRAFFIC_VERIFY_CONSECUTIVE
        max_attempts = Constants::TRAFFIC_VERIFY_ATTEMPTS

        max_attempts.times do |attempt|
          begin
            result = check_public_url(@ssh, public_url)

            if result[:success]
              consecutive_success += 1
              @log.success "[%d/%d] Public URL responding: %s", consecutive_success, required_consecutive, result[:http_code]

              if consecutive_success >= required_consecutive
                @log.success "Traffic switchover verified: public URL accessible"
                return
              end
            else
              if consecutive_success > 0
                @log.warning "Success streak broken at %d, restarting count", consecutive_success
              end
              consecutive_success = 0
              @log.info "[%d/%d] %s", attempt + 1, max_attempts, result[:message]
            end
          rescue SSHCommandError
            consecutive_success = 0
            @log.info "[%d/%d] Public URL check failed", attempt + 1, max_attempts
          end

          sleep(Constants::TRAFFIC_VERIFY_INTERVAL)
        end

        raise DeploymentError.new(
          "traffic_verification",
          "public URL verification failed after #{max_attempts} attempts. Cloudflare tunnel may not be routing correctly."
        )
      end

      # Check public URL for both status code and error header
      # Returns { success: bool, http_code: string, message: string }
      def check_public_url(ssh, url)
        # Get headers and status code with GET request (not HEAD - some apps don't support it)
        # -s = silent, -i = include headers, -o /dev/null would discard body but we need headers
        curl_cmd = "curl -si -m 10 '#{url}' 2>/dev/null"
        output = ssh.execute(curl_cmd).strip

        # Parse HTTP status code from first line (e.g., "HTTP/2 200" or "HTTP/1.1 200 OK")
        http_code = output.lines.first&.match(/HTTP\/[\d.]+ (\d+)/)&.captures&.first || "000"

        # Check for X-Nvoi-Error header (case-insensitive)
        has_error_header = output.lines.any? { |line| line.downcase.start_with?("x-nvoi-error:") }

        if http_code == "200" && !has_error_header
          { success: true, http_code: http_code, message: "OK" }
        elsif has_error_header
          { success: false, http_code: http_code, message: "Error backend responding (X-Nvoi-Error header present) - app is down" }
        else
          { success: false, http_code: http_code, message: "HTTP #{http_code} (expected: 200)" }
        end
      end

      private

        def run_pre_run_command(service_name, command)
          @log.info "Running pre-run command: %s", command

          # Get pod name
          pod_label = @namer.app_pod_label(service_name)
          pod_name = @ssh.execute("kubectl get pod -l #{pod_label} -o jsonpath='{.items[0].metadata.name}'")
          pod_name = pod_name.strip.delete("'")

          # Execute command in pod
          escaped_command = command.gsub("'", "'\"'\"'")
          exec_cmd = "kubectl exec #{pod_name} -- sh -c '#{escaped_command}'"

          begin
            output = @ssh.execute(exec_cmd)
            @log.info "Pre-run command output:\n%s", output unless output.empty?
          rescue SSHCommandError => e
            @log.error "Pre-run command failed: %s", e.message

            # Get pod logs for debugging
            logs = @ssh.execute("kubectl logs #{pod_name} --tail=50")
            @log.error "Pod logs:\n%s", logs

            raise DeploymentError.new("pre_run_command", "deployment aborted: pre-run command failed: #{e.message}")
          end
        end

        def wait_for_statefulset(name, namespace: "default", timeout: 300)
          @ssh.execute("kubectl rollout status statefulset/#{name} -n #{namespace} --timeout=#{timeout}s")
        end
    end
  end
end
