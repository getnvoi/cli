# frozen_string_literal: true

module Nvoi
  class Cli
    module Deploy
      module Steps
        # CleanupImages handles cleanup of old container images
        class CleanupImages
          def initialize(config, ssh, log)
            @config = config
            @ssh = ssh
            @log = log
          end

          def run(current_tag)
            keep_count = @config.keep_count_value
            prefix = @config.container_prefix

            @log.info "Cleaning up old images (keeping %d)", keep_count

            containerd = External::Containerd.new(@ssh)

            # List all images
            all_tags = containerd.list_images("#{prefix}:*")

            # Sort by tag (timestamp), keep newest
            sorted_tags = all_tags.sort.reverse
            keep_tags = sorted_tags.take(keep_count)

            # Make sure current tag is kept
            keep_tags << current_tag unless keep_tags.include?(current_tag)
            keep_tags << "latest"

            containerd.cleanup_old_images(prefix, keep_tags.uniq)

            @log.success "Old images cleaned up"
          end
        end
      end
    end
  end
end
