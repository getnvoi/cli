# frozen_string_literal: true

module Nvoi
  module External
    # Containerd manages container operations on remote servers via containerd/ctr
    # Used for image listing and cleanup on the remote server
    class Containerd
      attr_reader :ssh

      def initialize(ssh)
        @ssh = ssh
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
