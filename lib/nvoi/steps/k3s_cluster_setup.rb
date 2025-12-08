# frozen_string_literal: true

module Nvoi
  module Steps
    # K3sClusterSetup coordinates K3s installation across master and worker nodes
    class K3sClusterSetup
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
        raise K8sError, "no master server group found" unless master_group

        # Setup K3s on master
        master_name = @config.namer.server_name(master_group, 1)
        master = @provider.find_server(master_name)
        raise K8sError, "master server not found: #{master_name}" unless master

        master_ssh = Remote::SSHExecutor.new(master.public_ipv4, @config.ssh_key_path)
        master_provisioner = K3sProvisioner.new(master_ssh, @log, server_role: master_group, server_name: master_name)
        master_provisioner.provision

        # Get cluster token and private IP from master
        cluster_token = master_provisioner.get_cluster_token
        master_private_ip = master_provisioner.get_private_ip

        # Setup K3s on worker nodes
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

      def setup_worker(worker_name, group_name, cluster_token, master_private_ip, master_ssh)
        @log.info "Setting up K3s worker: %s", worker_name

        worker = @provider.find_server(worker_name)
        unless worker
          @log.warning "Worker server not found: %s", worker_name
          return
        end

        worker_ssh = Remote::SSHExecutor.new(worker.public_ipv4, @config.ssh_key_path)
        worker_provisioner = K3sProvisioner.new(worker_ssh, @log, server_role: group_name, server_name: worker_name)
        worker_provisioner.cluster_token = cluster_token
        worker_provisioner.main_server_private_ip = master_private_ip
        worker_provisioner.provision

        # Label worker node from master
        @log.info "Labeling worker node: %s", worker_name
        label_worker_from_master(master_ssh, worker_name, group_name)
      end

      def label_worker_from_master(master_ssh, worker_name, group_name)
        # Wait for node to join cluster
        30.times do
          output = master_ssh.execute("kubectl get nodes -o name")
          if output.include?(worker_name)
            master_ssh.execute("kubectl label node #{worker_name} nvoi.io/server-name=#{group_name} --overwrite")
            @log.success "Worker labeled: %s", worker_name
            return
          end
        rescue SSHCommandError
          # Not ready
        ensure
          sleep(5)
        end

        @log.warning "Worker node did not join cluster in time: %s", worker_name
      end
    end
  end
end
