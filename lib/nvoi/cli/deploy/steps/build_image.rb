# frozen_string_literal: true

module Nvoi
  class Cli
    module Deploy
      module Steps
        # BuildImage handles Docker image building and pushing to cluster
        class BuildImage
          def initialize(config, ssh, log)
            @config = config
            @ssh = ssh
            @log = log
          end

          def run(working_dir, image_tag)
            @log.info "Building Docker image: %s", image_tag

            containerd = External::Containerd.new(@ssh)
            containerd.build_and_deploy_image(working_dir, image_tag, cache_from: @config.namer.latest_image_tag)

            @log.success "Image built: %s", image_tag
          end
        end
      end
    end
  end
end
