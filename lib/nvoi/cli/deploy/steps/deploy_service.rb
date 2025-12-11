# frozen_string_literal: true

module Nvoi
  class Cli
    module Deploy
      module Steps
        # DeployService handles K8s deployment of all services
        class DeployService
          DEFAULT_RESOURCES = {
            request_memory: "128Mi",
            request_cpu: "100m",
            limit_memory: "512Mi",
            limit_cpu: "500m"
          }.freeze

          def initialize(config, ssh, tunnels, log)
            @config = config
            @ssh = ssh
            @tunnels = tunnels
            @log = log
            @namer = config.namer
            @kubectl = External::Kubectl.new(ssh)
          end

          def run(image_tag, timestamp)
            # Push to in-cluster registry
            registry_tag = "localhost:#{Utils::Constants::REGISTRY_PORT}/#{@config.container_prefix}:#{timestamp}"
            push_to_registry(image_tag, registry_tag)

            # Gather env vars
            first_service = @config.deploy.application.app.keys.first
            all_env = @config.env_for_service(first_service)

            # Deploy app secret
            deploy_app_secret(all_env)

            # Deploy database if configured
            db_config = @config.deploy.application.database
            if db_config
              db_spec = db_config.to_service_spec(@namer)
              deploy_database(db_spec) if db_spec
            end

            # Deploy additional services
            @config.deploy.application.services.each do |service_name, service_config|
              service_spec = service_config.to_service_spec(@config.deploy.application.name, service_name)
              deploy_service(service_name, service_spec)
            end

            # Deploy app services
            @config.deploy.application.app.each do |service_name, service_config|
              service_env = @config.env_for_service(service_name)
              deploy_app_service(service_name, service_config, registry_tag, service_env)

              # Deploy cloudflared for services with tunnels
              tunnel = @tunnels.find { |t| t.service_name == service_name }
              if tunnel
                deploy_cloudflared(service_name, tunnel.tunnel_token)
                verify_traffic_switchover(service_config)
              end
            end

            @log.success "All services deployed"
          end

          private

            def push_to_registry(local_tag, registry_tag)
              @log.info "Pushing to in-cluster registry: %s", registry_tag

              @ssh.execute("sudo ctr -n k8s.io images tag #{local_tag} #{registry_tag}")
              @ssh.execute("sudo ctr -n k8s.io images push --plain-http #{registry_tag}")

              @log.success "Image pushed to registry"
            end

            def deploy_app_secret(env_vars)
              secret_name = @namer.app_secret_name

              @log.info "Deploying app secret: %s", secret_name

              Utils::Templates.apply_manifest(@ssh, "app-secret.yaml", {
                name: secret_name,
                env_vars: env_vars
              })

              @log.success "App secret deployed"
            end

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

              # Use hostPath for database volume if configured
              db_mount = @config.deploy.application.database.mount
              if db_mount && !db_mount.empty?
                server_name = db_spec.servers.first
                vol_name = db_mount.keys.first
                data[:host_path] = @namer.server_volume_host_path(server_name, vol_name)
              end

              # Create database secret
              Utils::Templates.apply_manifest(@ssh, "app-secret.yaml", {
                name: @namer.database_secret_name,
                env_vars: db_spec.secrets
              })

              # Deploy StatefulSet
              Utils::Templates.apply_manifest(@ssh, "db-statefulset.yaml", data)

              # Wait for database to be ready
              @log.info "Waiting for database to be ready..."
              @kubectl.wait_for_statefulset(db_spec.name)

              @log.success "Database deployed: %s", db_spec.name
            end

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
                volume_path: volume_path,
                host_path: host_path,
                affinity_server_names: service_spec.servers
              }

              Utils::Templates.apply_manifest(@ssh, "service-deployment.yaml", data)

              @log.success "Service deployed: %s", service_spec.name
            end

            def deploy_app_service(service_name, service_config, image_tag, env)
              deployment_name = @namer.app_deployment_name(service_name)
              @log.info "Deploying app service: %s", deployment_name

              has_port = service_config.port && service_config.port.positive?
              template = has_port ? "app-deployment.yaml" : "worker-deployment.yaml"

              # Build probes
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
                readiness_probe: readiness_probe,
                liveness_probe: liveness_probe,
                volume_mounts: [],
                host_path_volumes: [],
                volumes: []
              }

              # Add mounts if configured
              if service_config.mounts && !service_config.mounts.empty?
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
                  unless server_config&.volumes&.key?(vol_name)
                    available = server_config&.volumes&.keys&.join(", ") || "none"
                    raise DeploymentError.new(
                      "validation",
                      "app '#{service_name}' mounts '#{vol_name}' but server '#{server_name}' " \
                      "has no volume named '#{vol_name}'. Available: #{available}"
                    )
                  end

                  host_path = @namer.server_volume_host_path(server_name, vol_name)
                  data[:volume_mounts] << { name: vol_name, mount_path: mount_path }
                  data[:host_path_volumes] << { name: vol_name, host_path: host_path }
                end
              end

              Utils::Templates.apply_manifest(@ssh, template, data)

              # Deploy service if it has a port
              if has_port
                Utils::Templates.apply_manifest(@ssh, "app-service.yaml", {
                  name: deployment_name,
                  port: service_config.port
                })
              end

              # Deploy ingress if domain is specified
              if service_config.domain && !service_config.domain.empty?
                hostname = Utils::Namer.build_hostname(service_config.subdomain, service_config.domain)

                Utils::Templates.apply_manifest(@ssh, "app-ingress.yaml", {
                  name: deployment_name,
                  domain: hostname,
                  port: service_config.port
                })
              end

              # Wait for deployment
              @log.info "Waiting for deployment to be ready..."
              @kubectl.wait_for_deployment(deployment_name)

              # Run pre-run command if specified
              if service_config.pre_run_command && !service_config.pre_run_command.empty?
                run_pre_run_command(service_name, service_config.pre_run_command)
              end

              @log.success "App service deployed: %s", deployment_name
            end

            def deploy_cloudflared(service_name, tunnel_token)
              deployment_name = @namer.cloudflared_deployment_name(service_name)
              @log.info "Deploying cloudflared: %s", deployment_name

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

            def verify_traffic_switchover(service_config)
              return unless service_config.domain && !service_config.domain.empty?

              hostname = Utils::Namer.build_hostname(service_config.subdomain, service_config.domain)

              health_path = service_config.healthcheck&.path || "/"
              public_url = "https://#{hostname}#{health_path}"

              @log.info "Verifying public traffic routing"
              @log.info "Testing: %s", public_url

              consecutive_success = 0
              required_consecutive = Utils::Constants::TRAFFIC_VERIFY_CONSECUTIVE
              max_attempts = Utils::Constants::TRAFFIC_VERIFY_ATTEMPTS

              max_attempts.times do |attempt|
                begin
                  result = check_public_url(public_url)

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
                rescue SshCommandError
                  consecutive_success = 0
                  @log.info "[%d/%d] Public URL check failed", attempt + 1, max_attempts
                end

                sleep(Utils::Constants::TRAFFIC_VERIFY_INTERVAL)
              end

              raise DeploymentError.new(
                "traffic_verification",
                "public URL verification failed after #{max_attempts} attempts. Cloudflare tunnel may not be routing correctly."
              )
            end

            def check_public_url(url)
              curl_cmd = "curl -si -m 10 '#{url}' 2>/dev/null"
              output = @ssh.execute(curl_cmd).strip

              http_code = output.lines.first&.match(/HTTP\/[\d.]+ (\d+)/)&.captures&.first || "000"
              has_error_header = output.lines.any? { |line| line.downcase.start_with?("x-nvoi-error:") }

              if http_code == "200" && !has_error_header
                { success: true, http_code: http_code, message: "OK" }
              elsif has_error_header
                { success: false, http_code: http_code, message: "Error backend responding (X-Nvoi-Error header present) - app is down" }
              else
                { success: false, http_code: http_code, message: "HTTP #{http_code} (expected: 200)" }
              end
            end

            def run_pre_run_command(service_name, command)
              @log.info "Running pre-run command: %s", command

              pod_label = @namer.app_pod_label(service_name)
              pod_name = @ssh.execute("kubectl get pod -l #{pod_label} -o jsonpath='{.items[0].metadata.name}'")
              pod_name = pod_name.strip.delete("'")

              escaped_command = command.gsub("'", "'\"'\"'")
              exec_cmd = "kubectl exec #{pod_name} -- sh -c '#{escaped_command}'"

              begin
                output = @ssh.execute(exec_cmd)
                @log.info "Pre-run command output:\n%s", output unless output.empty?
              rescue SshCommandError => e
                @log.error "Pre-run command failed: %s", e.message

                logs = @ssh.execute("kubectl logs #{pod_name} --tail=50")
                @log.error "Pod logs:\n%s", logs

                raise DeploymentError.new("pre_run_command", "deployment aborted: pre-run command failed: #{e.message}")
              end
            end
        end
      end
    end
  end
end
