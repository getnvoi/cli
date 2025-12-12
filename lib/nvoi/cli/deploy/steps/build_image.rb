# frozen_string_literal: true

module Nvoi
  class Cli
    module Deploy
      module Steps
        # BuildImage handles Docker image building and pushing to registry
        class BuildImage
          def initialize(config, log)
            @config = config
            @log = log
          end

          # Build locally and push to registry via SSH tunnel
          # Returns the registry tag for use in k8s deployments
          def run(working_dir, image_tag)
            @log.info "Building Docker image: %s", image_tag

            build_image(working_dir, image_tag)
            registry_tag = push_to_registry(image_tag)

            @log.success "Image built and pushed: %s", registry_tag
            registry_tag
          end

          private

            def build_image(working_dir, tag)
              cache_from = @config.namer.latest_image_tag
              cache_args = "--cache-from #{cache_from}"

              build_cmd = [
                "cd #{working_dir} &&",
                "DOCKER_BUILDKIT=1 docker build",
                "--platform linux/amd64",
                cache_args,
                "--build-arg BUILDKIT_INLINE_CACHE=1",
                "-t #{tag} ."
              ].join(" ")

              unless system("bash", "-c", build_cmd)
                raise Errors::SshError, "docker build failed"
              end

              # Tag as :latest for next build's cache
              system("docker", "tag", tag, cache_from)
            end

            def push_to_registry(tag)
              registry_port = Utils::Constants::REGISTRY_PORT
              registry_tag = "localhost:#{registry_port}/#{@config.container_prefix}:#{tag.split(':').last}"

              @log.info "Tagging for registry: %s", registry_tag
              unless system("docker", "tag", tag, registry_tag)
                raise Errors::SshError, "docker tag failed"
              end

              @log.info "Pushing to registry via SSH tunnel..."
              unless system("docker", "push", registry_tag)
                raise Errors::SshError, "docker push failed - is the SSH tunnel active?"
              end

              registry_tag
            end
        end
      end
    end
  end
end
