# frozen_string_literal: true

module Nvoi
  module External
    # Containerd manages container operations on remote servers via containerd/ctr
    class Containerd
      attr_reader :ssh

      def initialize(ssh)
        @ssh = ssh
      end

      # Build image locally, save to tar, rsync to remote, load with containerd
      def build_and_deploy_image(path, tag, cache_from: nil)
        cache_args = cache_from ? "--cache-from #{cache_from}" : ""
        local_build_cmd = "cd #{path} && DOCKER_BUILDKIT=1 docker build --platform linux/amd64 #{cache_args} --build-arg BUILDKIT_INLINE_CACHE=1 -t #{tag} ."

        unless system("bash", "-c", local_build_cmd)
          raise Errors::SshError, "local build failed"
        end

        # Tag as :latest for next build's cache
        system("docker", "tag", tag, cache_from) if cache_from

        tar_file = "/tmp/#{tag.tr(':', '_')}.tar"
        unless system("docker", "save", tag, "-o", tar_file)
          raise Errors::SshError, "docker save failed"
        end

        begin
          remote_tar_path = "/tmp/#{tag.tr(':', '_')}.tar"
          rsync_cmd = [
            "rsync", "-avz",
            "-e", "ssh -i #{@ssh.ssh_key} -o StrictHostKeyChecking=no",
            tar_file,
            "#{@ssh.user}@#{@ssh.ip}:#{remote_tar_path}"
          ]

          unless system(*rsync_cmd)
            raise Errors::SshError, "rsync failed"
          end

          Nvoi.logger.info "Importing image into containerd..."
          @ssh.execute("sudo ctr -n k8s.io images import #{remote_tar_path}")

          full_image_ref = "docker.io/library/#{tag}"

          begin
            @ssh.execute("sudo ctr -n k8s.io images tag #{full_image_ref} #{tag}")
          rescue Errors::SshCommandError => e
            list_output = @ssh.execute("sudo ctr -n k8s.io images ls") rescue ""
            raise Errors::SshError, "failed to tag imported image: #{e.message}\nAvailable images:\n#{list_output}"
          end

          @ssh.execute_ignore_errors("rm #{remote_tar_path}")
        ensure
          File.delete(tar_file) if File.exist?(tar_file)
        end
      end

      def list_images(filter)
        output = @ssh.execute("sudo ctr -n k8s.io images ls -q | grep '#{filter}' | sort -r")
        return [] if output.empty?

        output.split("\n")
      rescue Errors::SshCommandError
        []
      end

      def cleanup_old_images(prefix, keep_tags)
        all_images = list_images(prefix)
        return if all_images.empty?

        remove_images = all_images.reject do |img|
          keep_tags.any? { |tag| img.include?(tag) }
        end

        return if remove_images.empty?

        remove_images.each do |img|
          @ssh.execute_ignore_errors("sudo ctr -n k8s.io images rm #{img}")
        end
      end
    end
  end
end
