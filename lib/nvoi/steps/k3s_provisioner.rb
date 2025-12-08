# frozen_string_literal: true

module Nvoi
  module Steps
    # K3sProvisioner handles K3s installation and server setup
    class K3sProvisioner
      attr_accessor :main_server_ip, :main_server_private_ip, :cluster_token

      def initialize(ssh, log, k3s_version: nil, enable_k3s: true, server_role: nil, server_name: nil)
        @ssh = ssh
        @log = log
        @k3s_version = k3s_version || Constants::DEFAULT_K3S_VERSION
        @enable_k3s = enable_k3s
        @server_role = server_role
        @server_name = server_name
      end

      def provision
        @log.info "Starting K3s provisioning"

        wait_for_cloud_init

        if @enable_k3s
          is_master = @cluster_token.nil? || @cluster_token.empty?

          if is_master
            install_k3s_server
            label_node(@server_name, { "nvoi.io/server-name" => @server_role })
            setup_registry
            setup_ingress_controller
          else
            install_k3s_agent
          end
        end

        @log.success "K3s provisioning complete"
      end

      def get_cluster_token
        @log.info "Retrieving K3s cluster token"
        output = @ssh.execute("sudo cat /var/lib/rancher/k3s/server/node-token")
        token = output.strip
        raise K8sError, "cluster token is empty" if token.empty?

        @log.success "Cluster token retrieved"
        token
      end

      def get_private_ip
        output = @ssh.execute("ip addr show | grep 'inet 10\\.' | awk '{print $2}' | cut -d/ -f1 | head -1")
        private_ip = output.strip
        raise SSHError, "private IP not found" if private_ip.empty?

        private_ip
      end

      private

      def wait_for_cloud_init
        @log.info "Waiting for cloud-init to complete"

        60.times do
          begin
            output = @ssh.execute("test -f /var/lib/cloud/instance/boot-finished && echo 'ready'")
            if output.include?("ready")
              @log.success "Cloud-init complete"
              return
            end
          rescue SSHCommandError
            # Not ready yet
          end
          sleep(5)
        end

        raise K8sError, "cloud-init timeout"
      end

      def install_k3s_server
        # Check if K3s is already running
        begin
          @ssh.execute("systemctl is-active k3s")
          @log.info "K3s already running, skipping installation"
          setup_kubeconfig
          return
        rescue SSHCommandError
          # Not running, continue
        end

        @log.info "Installing K3s server"

        # Detect private IP and interface
        private_ip = get_private_ip
        private_iface = @ssh.execute("ip addr show | grep 'inet 10\\.' | awk '{print $NF}' | head -1").strip

        @log.info "Installing k3s on private IP: %s, interface: %s", private_ip, private_iface

        # Install Docker for image building
        install_docker(private_ip)

        # Configure k3s registries
        configure_registries

        # Install K3s with full configuration
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

        @ssh.execute(install_cmd, stream: true)
        @log.success "K3s server installed"

        setup_kubeconfig(private_ip)
        wait_for_k3s_ready
      end

      def install_k3s_agent
        # Check if K3s agent is already running
        begin
          @ssh.execute("systemctl is-active k3s-agent")
          @log.info "K3s agent already running, skipping installation"
          return
        rescue SSHCommandError
          # Not running, continue
        end

        @log.info "Installing K3s agent"

        private_ip = get_private_ip
        private_iface = @ssh.execute("ip addr show | grep 'inet 10\\.' | awk '{print $NF}' | head -1").strip

        @log.info "Worker private IP: %s, interface: %s", private_ip, private_iface

        cmd = <<~CMD
          curl -sfL https://get.k3s.io | K3S_URL="https://#{@main_server_private_ip}:6443" K3S_TOKEN="#{@cluster_token}" sh -s - agent \
            --node-ip=#{private_ip} \
            --flannel-iface=#{private_iface} \
            --node-name=#{@server_name}
        CMD

        @ssh.execute(cmd, stream: true)
        @log.success "K3s agent installed"
      end

      def install_docker(private_ip)
        # Check if Docker is already installed and running
        begin
          @ssh.execute("systemctl is-active docker")
          @log.info "Docker already running, skipping installation"
        rescue SSHCommandError
          # Not running, install it
          docker_install = <<~CMD
            sudo apt-get update && sudo apt-get install -y docker.io
            sudo systemctl start docker
            sudo systemctl enable docker
            sudo usermod -aG docker deploy
          CMD

          @ssh.execute(docker_install, stream: true)
        end

        # Configure Docker for insecure registry
        docker_config = <<~CMD
          sudo mkdir -p /etc/docker
          sudo tee /etc/docker/daemon.json > /dev/null <<EOF
          {"insecure-registries": ["#{private_ip}:5001", "localhost:30500"]}
          EOF
          sudo systemctl restart docker
        CMD

        @ssh.execute(docker_config)

        # Add registry domain to /etc/hosts
        @ssh.execute('grep -q "nvoi-registry.default.svc.cluster.local" /etc/hosts || echo "127.0.0.1 nvoi-registry.default.svc.cluster.local" | sudo tee -a /etc/hosts')
      end

      def configure_registries
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

        @ssh.execute(config)
      end

      def setup_kubeconfig(private_ip = nil)
        private_ip ||= get_private_ip

        cmd = <<~CMD
          sudo mkdir -p /home/deploy/.kube
          sudo cp /etc/rancher/k3s/k3s.yaml /home/deploy/.kube/config
          sudo sed -i "s/127.0.0.1/#{private_ip}/g" /home/deploy/.kube/config
          sudo chown -R deploy:deploy /home/deploy/.kube
        CMD

        @ssh.execute(cmd)
      end

      def wait_for_k3s_ready
        @log.info "Waiting for K3s to be ready"

        60.times do
          begin
            output = @ssh.execute("kubectl get nodes")
            if output.include?("Ready")
              @log.success "K3s is ready"
              return
            end
          rescue SSHCommandError
            # Not ready yet
          end
          sleep(5)
        end

        raise K8sError, "K3s failed to become ready"
      end

      def label_node(node_name, labels)
        # Get actual node name from K3s
        actual_node = @ssh.execute("kubectl get nodes -o jsonpath='{.items[0].metadata.name}'").strip

        labels.each do |key, value|
          @ssh.execute("kubectl label node #{actual_node} #{key}=#{value} --overwrite")
        end
      end

      def setup_registry
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

        @ssh.execute("cat <<'EOF' | kubectl apply -f -\n#{manifest}\nEOF")

        # Wait for registry to be ready
        @log.info "Waiting for registry to be ready"
        24.times do
          begin
            output = @ssh.execute("kubectl get deployment nvoi-registry -n default -o jsonpath='{.status.readyReplicas}'")
            if output.strip == "1"
              @log.success "In-cluster registry running on :30500"
              return
            end
          rescue SSHCommandError
            # Not ready
          end
          sleep(5)
        end

        raise K8sError, "registry failed to become ready"
      end

      def setup_ingress_controller
        @log.info "Setting up NGINX Ingress Controller"

        @ssh.execute("kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/baremetal/deploy.yaml", stream: true)

        # Wait for ingress controller
        @log.info "Waiting for NGINX Ingress Controller to be ready"
        60.times do
          begin
            ready = @ssh.execute("kubectl get deployment ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.readyReplicas}'").strip
            desired = @ssh.execute("kubectl get deployment ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.replicas}'").strip

            if !ready.empty? && !desired.empty? && ready == desired
              @log.success "NGINX Ingress Controller is ready"
              return
            end
          rescue SSHCommandError
            # Not ready
          end
          sleep(10)
        end

        raise K8sError, "NGINX Ingress Controller failed to become ready"
      end
    end
  end
end
