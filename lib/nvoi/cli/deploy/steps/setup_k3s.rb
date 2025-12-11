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
            cluster_token, master_private_ip = provision_master(master_ssh, master_group, master_name)

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

            def provision_master(ssh, server_role, server_name)
              wait_for_cloud_init(ssh)

              # Check if K3s is already running
              begin
                ssh.execute("systemctl is-active k3s")
                @log.info "K3s already running, skipping installation"
                setup_kubeconfig(ssh)
                token = get_cluster_token(ssh)
                private_ip = get_private_ip(ssh)
                return [token, private_ip]
              rescue Errors::SshCommandError
                # Not running, continue installation
              end

              @log.info "Installing K3s server"

              private_ip = get_private_ip(ssh)
              private_iface = ssh.execute("ip addr show | grep 'inet 10\\.' | awk '{print $NF}' | head -1").strip

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

              # Check if K3s agent is already running
              begin
                worker_ssh.execute("systemctl is-active k3s-agent")
                @log.info "K3s agent already running on %s", worker_name
                return
              rescue Errors::SshCommandError
                # Not running, continue
              end

              @log.info "Installing K3s agent on %s", worker_name

              private_ip = get_private_ip(worker_ssh)
              private_iface = worker_ssh.execute("ip addr show | grep 'inet 10\\.' | awk '{print $NF}' | head -1").strip

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

              60.times do
                begin
                  output = ssh.execute("test -f /var/lib/cloud/instance/boot-finished && echo 'ready'")
                  if output.include?("ready")
                    @log.success "Cloud-init complete"
                    return
                  end
                rescue Errors::SshCommandError
                  # Not ready yet
                end
                sleep(5)
              end

              raise Errors::K8sError, "cloud-init timeout"
            end

            def get_cluster_token(ssh)
              @log.info "Retrieving K3s cluster token"
              output = ssh.execute("sudo cat /var/lib/rancher/k3s/server/node-token")
              token = output.strip
              raise Errors::K8sError, "cluster token is empty" if token.empty?

              @log.success "Cluster token retrieved"
              token
            end

            def get_private_ip(ssh)
              output = ssh.execute("ip addr show | grep 'inet 10\\.' | awk '{print $2}' | cut -d/ -f1 | head -1")
              private_ip = output.strip
              raise Errors::SshError, "private IP not found" if private_ip.empty?

              private_ip
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
              private_ip ||= get_private_ip(ssh)

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

              60.times do
                begin
                  output = ssh.execute("kubectl get nodes")
                  if output.include?("Ready")
                    @log.success "K3s is ready"
                    return
                  end
                rescue Errors::SshCommandError
                  # Not ready yet
                end
                sleep(5)
              end

              raise Errors::K8sError, "K3s failed to become ready"
            end

            def label_node(ssh, node_name, labels)
              actual_node = ssh.execute("kubectl get nodes -o jsonpath='{.items[0].metadata.name}'").strip

              labels.each do |key, value|
                ssh.execute("kubectl label node #{actual_node} #{key}=#{value} --overwrite")
              end
            end

            def label_worker_from_master(master_ssh, worker_name, group_name)
              @log.info "Labeling worker node: %s", worker_name

              30.times do
                begin
                  output = master_ssh.execute("kubectl get nodes -o name")
                  if output.include?(worker_name)
                    master_ssh.execute("kubectl label node #{worker_name} nvoi.io/server-name=#{group_name} --overwrite")
                    @log.success "Worker labeled: %s", worker_name
                    return
                  end
                rescue Errors::SshCommandError
                  # Not ready
                end
                sleep(5)
              end

              @log.warning "Worker node did not join cluster in time: %s", worker_name
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
              24.times do
                begin
                  output = ssh.execute("kubectl get deployment nvoi-registry -n default -o jsonpath='{.status.readyReplicas}'")
                  if output.strip == "1"
                    @log.success "In-cluster registry running on :30500"
                    return
                  end
                rescue Errors::SshCommandError
                  # Not ready
                end
                sleep(5)
              end

              raise Errors::K8sError, "registry failed to become ready"
            end

            def setup_ingress_controller(ssh)
              @log.info "Setting up NGINX Ingress Controller"

              ssh.execute("kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/baremetal/deploy.yaml", stream: true)

              @log.info "Waiting for NGINX Ingress Controller to be ready"
              60.times do
                begin
                  ready = ssh.execute("kubectl get deployment ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.readyReplicas}'").strip
                  desired = ssh.execute("kubectl get deployment ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.replicas}'").strip

                  if !ready.empty? && !desired.empty? && ready == desired
                    @log.success "NGINX Ingress Controller is ready"
                    deploy_error_backend(ssh)
                    configure_custom_error_pages(ssh)
                    return
                  end
                rescue Errors::SshCommandError
                  # Not ready
                end
                sleep(10)
              end

              raise Errors::K8sError, "NGINX Ingress Controller failed to become ready"
            end

            def deploy_error_backend(ssh)
              @log.info "Deploying custom error backend"

              manifest = Utils::Templates.load_template_content("error-backend.yaml.erb")
              ssh.execute("cat <<'EOF' | kubectl apply -f -\n#{manifest}\nEOF")

              30.times do
                begin
                  ready = ssh.execute("kubectl get deployment nvoi-error-backend -n ingress-nginx -o jsonpath='{.status.readyReplicas}'").strip
                  if ready == "1"
                    @log.success "Error backend is ready"
                    return
                  end
                rescue Errors::SshCommandError
                  # Not ready
                end
                sleep(2)
              end

              raise Errors::K8sError, "Error backend failed to become ready"
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
