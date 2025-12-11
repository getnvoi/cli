# frozen_string_literal: true

module Nvoi
  module External
    # Kubectl handles kubernetes operations via kubectl on remote servers
    class Kubectl
      attr_reader :ssh

      def initialize(ssh)
        @ssh = ssh
      end

      def apply(manifest)
        cmd = "cat <<'EOF' | kubectl apply -f -\n#{manifest}\nEOF"
        @ssh.execute(cmd)
      end

      def delete(resource_type, name, namespace: "default")
        @ssh.execute("kubectl delete #{resource_type} #{name} -n #{namespace} --ignore-not-found")
      end

      def get(resource_type, name, namespace: "default", jsonpath: nil)
        cmd = "kubectl get #{resource_type} #{name} -n #{namespace}"
        cmd += " -o jsonpath='#{jsonpath}'" if jsonpath
        @ssh.execute(cmd)
      end

      def exec(pod_name, command, namespace: "default")
        @ssh.execute("kubectl exec -n #{namespace} #{pod_name} -- #{command}")
      end

      def logs(pod_name, namespace: "default", tail: nil)
        cmd = "kubectl logs #{pod_name} -n #{namespace}"
        cmd += " --tail=#{tail}" if tail
        @ssh.execute(cmd)
      end

      def rollout_status(resource_type, name, namespace: "default", timeout: 300)
        @ssh.execute("kubectl rollout status #{resource_type}/#{name} -n #{namespace} --timeout=#{timeout}s")
      end

      def wait_for_deployment(name, namespace: "default", timeout: 300)
        rollout_status("deployment", name, namespace:, timeout:)
      end

      def wait_for_statefulset(name, namespace: "default", timeout: 300)
        rollout_status("statefulset", name, namespace:, timeout:)
      end

      def label_node(node_name, labels)
        labels.each do |key, value|
          @ssh.execute("kubectl label node #{node_name} #{key}=#{value} --overwrite")
        end
      end

      def get_nodes
        @ssh.execute("kubectl get nodes -o name")
      end

      def cp(local_path, pod_path, namespace: "default")
        @ssh.execute("kubectl cp #{local_path} #{namespace}/#{pod_path}")
      end
    end
  end
end
