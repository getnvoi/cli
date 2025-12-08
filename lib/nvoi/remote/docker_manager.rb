# frozen_string_literal: true

module Nvoi
  module Remote
    # ContainerRunOptions contains options for running a container
    ContainerRunOptions = Struct.new(:name, :image, :network, :volumes, :environment, :command, keyword_init: true)

    # WaitForHealthOptions contains options for health checking
    WaitForHealthOptions = Struct.new(:container, :utility_container, :health_check_path, :port,
                                      :max_attempts, :interval, :logger, keyword_init: true)

    # DockerManager manages Docker operations on remote servers
    class DockerManager
      attr_reader :ssh

      def initialize(ssh)
        @ssh = ssh
      end

      # Create a Docker network
      def create_network(name)
        @ssh.execute("docker network create #{name} 2>/dev/null || true")
      end

      # Build image locally, save to tar, rsync to remote, load on remote
      def build_image(path, tag, cache_from = nil)
        # 1. Build locally
        cache_args = cache_from ? "--cache-from #{cache_from}" : ""
        local_build_cmd = "cd #{path} && DOCKER_BUILDKIT=1 docker build --platform linux/amd64 #{cache_args} --build-arg BUILDKIT_INLINE_CACHE=1 -t #{tag} ."

        unless system("bash", "-c", local_build_cmd)
          raise SSHError, "local build failed"
        end

        # 2. Save to tar
        tar_file = "/tmp/#{tag.tr(':', '_')}.tar"
        unless system("docker", "save", tag, "-o", tar_file)
          raise SSHError, "docker save failed"
        end

        begin
          # 3. Rsync to remote
          remote_tar_path = "/tmp/#{tag.tr(':', '_')}.tar"
          rsync_cmd = ["rsync", "-avz",
                       "-e", "ssh -i #{@ssh.ssh_key} -o StrictHostKeyChecking=no",
                       tar_file,
                       "#{@ssh.user}@#{@ssh.ip}:#{remote_tar_path}"]

          unless system(*rsync_cmd)
            raise SSHError, "rsync failed"
          end

          # 4. Load on remote with ctr (containerd)
          output = @ssh.execute("sudo ctr -n k8s.io images import #{remote_tar_path}")

          # Docker saves images with docker.io/library/ prefix
          full_image_ref = "docker.io/library/#{tag}"

          # Tag the imported image with the simple name
          begin
            @ssh.execute("sudo ctr -n k8s.io images tag #{full_image_ref} #{tag}")
          rescue SSHCommandError => e
            list_output = @ssh.execute("sudo ctr -n k8s.io images ls") rescue ""
            raise SSHError, "failed to tag imported image: #{e.message}\nAvailable images:\n#{list_output}"
          end

          # Cleanup tar file
          @ssh.execute_quiet("rm #{remote_tar_path}")
        ensure
          File.delete(tar_file) if File.exist?(tar_file)
        end
      end

      # Run a container
      def run_container(opts)
        cmd = "docker run -d --name #{opts.name} --network #{opts.network}"

        opts.volumes&.each do |vol|
          cmd += " -v #{vol}"
        end

        opts.environment&.each do |k, v|
          # Escape single quotes in value
          escaped_v = v.to_s.gsub("'", "'\\''")
          cmd += " -e #{k}='#{escaped_v}'"
        end

        cmd += " --restart unless-stopped #{opts.image}"
        cmd += " #{opts.command}" if opts.command && !opts.command.empty?

        @ssh.execute(cmd)
      end

      # Execute a command inside a running container
      def exec(container, command)
        @ssh.execute("docker exec #{container} #{command}")
      end

      # Wait for a container to be healthy
      def wait_for_health(opts)
        interval = opts.interval || 3

        opts.max_attempts.times do |i|
          # Check container status
          begin
            status = @ssh.execute(
              "docker inspect --format='{{.State.Status}}' #{opts.container} 2>/dev/null || echo 'none'"
            )
          rescue SSHCommandError
            opts.logger&.info("[%d/%d] Failed to get container status", i + 1, opts.max_attempts)
            sleep(interval)
            next
          end

          # Get last log line
          log_line = @ssh.execute("docker logs --tail 1 #{opts.container} 2>&1") rescue ""

          opts.logger&.info("[%d/%d] Status: %s | %s", i + 1, opts.max_attempts, status, log_line.strip)

          if status == "running"
            # Check if app responds using utility container
            health_cmd = "docker exec #{opts.utility_container} curl -s -o /dev/null -w '%{http_code}' -m 2 http://#{opts.container}:#{opts.port}#{opts.health_check_path} 2>&1 || echo '000'"

            http_code = @ssh.execute(health_cmd) rescue "000"
            if http_code.include?("200")
              return true
            else
              code = http_code.length >= 3 ? http_code[-3..] : "000"
              opts.logger&.info("  App not ready yet (HTTP %s)", code)
            end
          end

          sleep(interval)
        end

        false
      end

      # Get container status
      def container_status(name)
        @ssh.execute("docker inspect --format='{{.State.Status}}' #{name} 2>/dev/null || echo 'none'")
      end

      # Get container logs
      def container_logs(name, lines)
        @ssh.execute("docker logs --tail #{lines} #{name} 2>&1")
      end

      # Stop a container
      def stop_container(name)
        @ssh.execute("docker stop #{name} 2>/dev/null || true")
      end

      # Remove a container
      def remove_container(name)
        @ssh.execute("docker rm #{name} 2>/dev/null || true")
      end

      # List containers matching a filter
      def list_containers(filter)
        output = @ssh.execute("docker ps -a --filter '#{filter}' --format '{{.Names}}' --no-trunc | sort -r")
        return [] if output.empty?

        output.split("\n")
      end

      # List images matching a filter
      def list_images(filter)
        output = @ssh.execute("docker images --filter '#{filter}' --format '{{.Tag}}' | sort -r")
        return [] if output.empty?

        output.split("\n")
      end

      # Cleanup old Docker images
      def cleanup_old_images(prefix, keep_tags)
        all_tags = list_images("reference=#{prefix}:*")

        remove_tags = all_tags.reject { |tag| keep_tags.include?(tag) }
        return if remove_tags.empty?

        images = remove_tags.map { |tag| "#{prefix}:#{tag}" }
        @ssh.execute("docker rmi #{images.join(' ')} 2>/dev/null || true")
      end

      # Check if a container is running
      def container_running?(name)
        output = @ssh.execute("docker ps -q -f name=^#{name}$ -f status=running 2>/dev/null")
        !output.empty?
      end

      # Setup a Cloudflare tunnel sidecar
      def setup_cloudflared(network, token, name)
        create_network(network)

        cmd = "docker run -d --name #{name} --network #{network} --restart always " \
              "cloudflare/cloudflared:latest tunnel run --token #{token}"

        @ssh.execute(cmd)
      end
    end
  end
end
