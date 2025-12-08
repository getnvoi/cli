# frozen_string_literal: true

module Nvoi
  module Deployer
    # Cleaner handles cleanup of old deployments and resources
    class Cleaner
      def initialize(config, docker_manager, log)
        @config = config
        @docker_manager = docker_manager
        @log = log
      end

      def cleanup_old_images(current_tag)
        keep_count = @config.keep_count_value
        prefix = @config.container_prefix

        @log.info "Cleaning up old images (keeping %d)", keep_count

        # List all images
        all_tags = @docker_manager.list_images("reference=#{prefix}:*")

        # Sort by tag (timestamp), keep newest
        sorted_tags = all_tags.sort.reverse
        keep_tags = sorted_tags.take(keep_count)

        # Make sure current tag is kept
        keep_tags << current_tag unless keep_tags.include?(current_tag)
        keep_tags << "latest"

        @docker_manager.cleanup_old_images(prefix, keep_tags.uniq)

        @log.success "Old images cleaned up"
      end
    end
  end
end
