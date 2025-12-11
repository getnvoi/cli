# frozen_string_literal: true

module Nvoi
  class Cli
    module Deploy
      module Steps
        # SetupK3s handles K3s cluster installation and configuration
        class SetupK3s
          def initialize(config, provider, log, main_server_ip)
            @config = config
            @provider = provider
            @log = log
            @main_server_ip = main_server_ip
          end

          def run
            @log.info "Setting up K3s cluster"

            # Find master server group
            master_group, master_config = find_master_group
            raise Errors::K8sError, "no master server group found" unless master_group

            # Setup K3s on master
            master_name = @config.namer.server_name(master_group, 1)
            master = @provider.find_server(master_name)
            raise Errors::K8sError, "master server not found: #{master_name}" unless master

            master_ssh = External::Ssh.new(master.public_ipv4, @config.ssh_key_path)

            # Provision master
            cluster_token, master_private_ip = provision_master(master_ssh, master_group, master_name, master.private_ipv4)

            # Setup workers
            @config.deploy.application.servers.each do |group_name, group_config|
              next if group_name == master_group
              next unless group_config

              count = group_config.count.positive? ? group_config.count : 1

              (1..count).each do |i|
                worker_name = @config.namer.server_name(group_name, i)
                setup_worker(worker_name, group_name, cluster_token, master_private_ip, master_ssh)
              end
            end

            @log.success "K3s cluster setup complete"
          end

          private

            def find_master_group
              @config.deploy.application.servers.each do |name, cfg|
                return [name, cfg] if cfg&.master
              end

              # If only one group, use it as master
              if @config.deploy.application.servers.size == 1
                return @config.deploy.application.servers.first
              end

              nil
            end

            def provision_master(ssh, server_role, server_name, private_ip)
              wait_for_cloud_init(ssh)

              # Discover private IP via SSH if not provided by provider
              private_ip ||= discover_private_ip(ssh)
              raise Errors::K8sError, "server has no private IP - ensure network is attached" unless private_ip

              # Check if K3s is already running
              begin
                ssh.execute("systemctl is-active k3s")
                @log.info "K3s already running, skipping installation"
                setup_kubeconfig(ssh)
                token = get_cluster_token(ssh)
                return [token, private_ip]
              rescue Errors::SshCommandError
                # Not running, continue installation
              end

              @log.info "Installing K3s server"

              private_iface = get_interface_for_ip(ssh, private_ip)

              @log.info "Installing k3s on private IP: %s, interface: %s", private_ip, private_iface

              # Install Docker for image building
              install_docker(ssh, private_ip)

              # Configure k3s registries
              configure_registries(ssh)

              # Install K3s
              install_cmd = <<~CMD
              curl -sfL https://get.k3s.io | sudo sh -s - server \
                --bind-address=#{private_ip} \
                --advertise-address=#{private_ip} \
                --node-ip=#{private_ip} \
                --tls-san=#{private_ip} \
                --flannel-iface=#{private_iface} \
                --flannel-backend=wireguard-native \
                --disable=traefik \
                --write-kubeconfig-mode=644 \
                --cluster-cidr=10.42.0.0/16 \
                --service-cidr=10.43.0.0/16
            CMD

              ssh.execute(install_cmd, stream: true)
              @log.success "K3s server installed"

              setup_kubeconfig(ssh, private_ip)
              wait_for_k3s_ready(ssh)

              # Label master node
              label_node(ssh, server_name, { "nvoi.io/server-name" => server_role })

              # Setup registry and ingress
              setup_registry(ssh)
              setup_ingress_controller(ssh)

              token = get_cluster_token(ssh)
              [token, private_ip]
            end

            def setup_worker(worker_name, group_name, cluster_token, master_private_ip, master_ssh)
              @log.info "Setting up K3s worker: %s", worker_name

              worker = @provider.find_server(worker_name)
              unless worker
                @log.warning "Worker server not found: %s", worker_name
                return
              end

              worker_ssh = External::Ssh.new(worker.public_ipv4, @config.ssh_key_path)
              wait_for_cloud_init(worker_ssh)

              # Discover private IP via SSH if not provided by provider
              private_ip = worker.private_ipv4 || discover_private_ip(worker_ssh)
              unless private_ip
                @log.warning "Worker %s has no private IP, skipping", worker_name
                return
              end

              # Check if K3s agent is already running
              begin
                worker_ssh.execute("systemctl is-active k3s-agent")
                @log.info "K3s agent already running on %s", worker_name
                return
              rescue Errors::SshCommandError
                # Not running, continue
              end

              @log.info "Installing K3s agent on %s", worker_name

              private_iface = get_interface_for_ip(worker_ssh, private_ip)

              cmd = <<~CMD
              curl -sfL https://get.k3s.io | K3S_URL="https://#{master_private_ip}:6443" K3S_TOKEN="#{cluster_token}" sh -s - agent \
                --node-ip=#{private_ip} \
                --flannel-iface=#{private_iface} \
                --node-name=#{worker_name}
            CMD

              worker_ssh.execute(cmd, stream: true)
              @log.success "K3s agent installed on %s", worker_name

              # Label worker node from master
              label_worker_from_master(master_ssh, worker_name, group_name)
            end

            def wait_for_cloud_init(ssh)
              @log.info "Waiting for cloud-init to complete"

              ready = Utils::Retry.poll(max_attempts: 60, interval: 5) do
                begin
                  output = ssh.execute("test -f /var/lib/cloud/instance/boot-finished && echo 'ready'")
                  output.include?("ready")
                rescue Errors::SshCommandError
                  false
                end
              end

              raise Errors::K8sError, "cloud-init timeout" unless ready

              @log.success "Cloud-init complete"
            end

            def get_cluster_token(ssh)
              @log.info "Retrieving K3s cluster token"
              output = ssh.execute("sudo cat /var/lib/rancher/k3s/server/node-token")
              token = output.strip
              raise Errors::K8sError, "cluster token is empty" if token.empty?

              @log.success "Cluster token retrieved"
              token
            end

            def discover_private_ip(ssh)
              # Match RFC1918 private ranges, exclude docker/bridge interfaces
              output = ssh.execute("ip addr show | grep -v 'docker\\|br-\\|veth' | grep -E 'inet (10\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.)' | awk '{print $2}' | cut -d/ -f1 | head -1")
              ip = output.strip
              ip.empty? ? nil : ip
            end

            def get_interface_for_ip(ssh, ip)
              # Find the interface that has this IP
              output = ssh.execute("ip addr show | grep 'inet #{ip}/' | awk '{print $NF}'").strip
              return output unless output.empty?

              # Fallback: find any interface with the IP prefix
              prefix = ip.split(".")[0..2].join(".")
              output = ssh.execute("ip addr show | grep -v 'docker\\|br-\\|veth' | grep 'inet #{prefix}\\.' | awk '{print $NF}' | head -1").strip
              output.empty? ? nil : output
            end

            def install_docker(ssh, private_ip)
              begin
                ssh.execute("systemctl is-active docker")
                @log.info "Docker already running, skipping installation"
              rescue Errors::SshCommandError
                docker_install = <<~CMD
                sudo apt-get update && sudo apt-get install -y docker.io
                sudo systemctl start docker
                sudo systemctl enable docker
                sudo usermod -aG docker deploy
              CMD

                ssh.execute(docker_install, stream: true)
              end

              # Configure Docker for insecure registry
              docker_config = <<~CMD
              sudo mkdir -p /etc/docker
              sudo tee /etc/docker/daemon.json > /dev/null <<EOF
              {"insecure-registries": ["#{private_ip}:5001", "localhost:30500"]}
              EOF
              sudo systemctl restart docker
            CMD

              ssh.execute(docker_config)

              # Add registry domain to /etc/hosts
              ssh.execute('grep -q "nvoi-registry.default.svc.cluster.local" /etc/hosts || echo "127.0.0.1 nvoi-registry.default.svc.cluster.local" | sudo tee -a /etc/hosts')
            end

            def configure_registries(ssh)
              config = <<~CMD
              sudo mkdir -p /etc/rancher/k3s
              sudo tee /etc/rancher/k3s/registries.yaml > /dev/null <<'REGEOF'
              mirrors:
                "nvoi-registry.default.svc.cluster.local:5000":
                  endpoint:
                    - "http://localhost:30500"
                "localhost:30500":
                  endpoint:
                    - "http://localhost:30500"
              configs:
                "nvoi-registry.default.svc.cluster.local:5000":
                  tls:
                    insecure_skip_verify: true
                "localhost:30500":
                  tls:
                    insecure_skip_verify: true
              REGEOF
            CMD

              ssh.execute(config)
            end

            def setup_kubeconfig(ssh, private_ip = nil)
              private_ip ||= discover_private_ip(ssh)

              cmd = <<~CMD
              sudo mkdir -p /home/deploy/.kube
              sudo cp /etc/rancher/k3s/k3s.yaml /home/deploy/.kube/config
              sudo sed -i "s/127.0.0.1/#{private_ip}/g" /home/deploy/.kube/config
              sudo chown -R deploy:deploy /home/deploy/.kube
            CMD

              ssh.execute(cmd)
            end

            def wait_for_k3s_ready(ssh)
              @log.info "Waiting for K3s to be ready"

              ready = Utils::Retry.poll(max_attempts: 60, interval: 5) do
                begin
                  output = ssh.execute("kubectl get nodes")
                  output.include?("Ready")
                rescue Errors::SshCommandError
                  false
                end
              end

              raise Errors::K8sError, "K3s failed to become ready" unless ready

              @log.success "K3s is ready"
            end

            def label_node(ssh, node_name, labels)
              actual_node = ssh.execute("kubectl get nodes -o jsonpath='{.items[0].metadata.name}'").strip

              labels.each do |key, value|
                ssh.execute("kubectl label node #{actual_node} #{key}=#{value} --overwrite")
              end
            end

            def label_worker_from_master(master_ssh, worker_name, group_name)
              @log.info "Labeling worker node: %s", worker_name

              joined = Utils::Retry.poll(max_attempts: 30, interval: 5) do
                begin
                  output = master_ssh.execute("kubectl get nodes -o name")
                  output.include?(worker_name)
                rescue Errors::SshCommandError
                  false
                end
              end

              unless joined
                @log.warning "Worker node did not join cluster in time: %s", worker_name
                return
              end

              master_ssh.execute("kubectl label node #{worker_name} nvoi.io/server-name=#{group_name} --overwrite")
              @log.success "Worker labeled: %s", worker_name
            end

            def setup_registry(ssh)
              @log.info "Setting up in-cluster registry"

              manifest = <<~YAML
              apiVersion: v1
              kind: Namespace
              metadata:
                name: nvoi-system
              ---
              apiVersion: apps/v1
              kind: Deployment
              metadata:
                name: nvoi-registry
                namespace: default
              spec:
                replicas: 1
                selector:
                  matchLabels:
                    app: nvoi-registry
                template:
                  metadata:
                    labels:
                      app: nvoi-registry
                  spec:
                    containers:
                    - name: registry
                      image: registry:2
                      ports:
                      - containerPort: 5000
                        protocol: TCP
                      env:
                      - name: REGISTRY_HTTP_ADDR
                        value: "0.0.0.0:5000"
                      volumeMounts:
                      - name: registry-storage
                        mountPath: /var/lib/registry
                    volumes:
                    - name: registry-storage
                      emptyDir: {}
              ---
              apiVersion: v1
              kind: Service
              metadata:
                name: nvoi-registry
                namespace: default
              spec:
                type: NodePort
                ports:
                - port: 5000
                  targetPort: 5000
                  nodePort: 30500
                selector:
                  app: nvoi-registry
            YAML

              ssh.execute("cat <<'EOF' | kubectl apply -f -\n#{manifest}\nEOF")

              # Wait for registry to be ready
              @log.info "Waiting for registry to be ready"

              ready = Utils::Retry.poll(max_attempts: 24, interval: 5) do
                begin
                  output = ssh.execute("kubectl get deployment nvoi-registry -n default -o jsonpath='{.status.readyReplicas}'")
                  output.strip == "1"
                rescue Errors::SshCommandError
                  false
                end
              end

              raise Errors::K8sError, "registry failed to become ready" unless ready

              @log.success "In-cluster registry running on :30500"
            end

            def setup_ingress_controller(ssh)
              @log.info "Setting up NGINX Ingress Controller"

              ssh.execute("kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/baremetal/deploy.yaml", stream: true)

              @log.info "Waiting for NGINX Ingress Controller to be ready"

              ready = Utils::Retry.poll(max_attempts: 60, interval: 10) do
                begin
                  ready_replicas = ssh.execute("kubectl get deployment ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.readyReplicas}'").strip
                  desired_replicas = ssh.execute("kubectl get deployment ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.replicas}'").strip

                  !ready_replicas.empty? && !desired_replicas.empty? && ready_replicas == desired_replicas
                rescue Errors::SshCommandError
                  false
                end
              end

              raise Errors::K8sError, "NGINX Ingress Controller failed to become ready" unless ready

              @log.success "NGINX Ingress Controller is ready"
              deploy_error_backend(ssh)
              configure_custom_error_pages(ssh)
            end

            def deploy_error_backend(ssh)
              @log.info "Deploying custom error backend"

              Utils::Templates.apply_manifest(ssh, "error-backend.yaml", {})

              ready = Utils::Retry.poll(max_attempts: 30, interval: 2) do
                begin
                  replicas = ssh.execute("kubectl get deployment nvoi-error-backend -n ingress-nginx -o jsonpath='{.status.readyReplicas}'").strip
                  replicas == "1"
                rescue Errors::SshCommandError
                  false
                end
              end

              raise Errors::K8sError, "Error backend failed to become ready" unless ready

              @log.success "Error backend is ready"
            end

            def configure_custom_error_pages(ssh)
              @log.info "Configuring custom error pages for 502, 503, 504"

              patch_cmd = <<~CMD
                kubectl patch configmap ingress-nginx-controller -n ingress-nginx --type merge -p '{"data":{"custom-http-errors":"502,503,504"}}'
              CMD

              ssh.execute(patch_cmd)

              check_cmd = "kubectl get deployment ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.template.spec.containers[0].args}'"
              current_args = ssh.execute(check_cmd)

              unless current_args.include?("--default-backend-service")
                patch_deployment = <<~CMD
                  kubectl patch deployment ingress-nginx-controller -n ingress-nginx --type=json -p='[
                    {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--default-backend-service=ingress-nginx/nvoi-error-backend"}
                  ]'
                CMD

                ssh.execute(patch_deployment)

                @log.info "Waiting for ingress controller to restart..."
                ssh.execute("kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=120s")
              else
                @log.info "Custom error backend already configured"
              end

              @log.success "Custom error pages configured"
            end
        end
      end
    end
  end
end
