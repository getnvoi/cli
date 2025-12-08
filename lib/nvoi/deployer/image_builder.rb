# frozen_string_literal: true

module Nvoi
  module Deployer
    # ImageBuilder handles Docker image building and pushing
    class ImageBuilder
      def initialize(config, docker_manager, log)
        @config = config
        @docker_manager = docker_manager
        @log = log
      end

      def build_and_push(working_dir, image_tag)
        @log.info "Building Docker image: %s", image_tag

        # Build image locally, transfer to remote, load with containerd
        @docker_manager.build_image(working_dir, image_tag, @config.namer.latest_image_tag)

        @log.success "Image built and pushed: %s", image_tag
      end
    end
  end
end
