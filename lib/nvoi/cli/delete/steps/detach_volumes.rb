# frozen_string_literal: true

module Nvoi
  class Cli
    module Delete
      module Steps
        # DetachVolumes handles volume detachment before server deletion
        class DetachVolumes
          def initialize(config, provider, log)
            @config = config
            @provider = provider
            @log = log
            @namer = config.namer
          end

          def run
            volume_names = collect_volume_names
            return if volume_names.empty?

            @log.info "Detaching %d volume(s)", volume_names.size

            volume_names.each do |vol_name|
              detach_volume(vol_name)
            end
          end

          private

            def collect_volume_names
              names = []

              @config.deploy.application.servers.each do |server_name, server_config|
                next unless server_config.volumes && !server_config.volumes.empty?

                server_config.volumes.each_key do |vol_name|
                  names << @namer.server_volume_name(server_name, vol_name)
                end
              end

              names
            end

            def detach_volume(vol_name)
              volume = @provider.get_volume_by_name(vol_name)
              return unless volume&.server_id && !volume.server_id.empty?

              @log.info "Detaching volume: %s", vol_name
              @provider.detach_volume(volume.id)
              @log.success "Volume detached: %s", vol_name
            rescue StandardError => e
              @log.warning "Failed to detach volume %s: %s", vol_name, e.message
            end
        end
      end
    end
  end
end
