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
            volume_configs = collect_volume_configs
            return if volume_configs.empty?

            @log.info "Detaching %d volume(s)", volume_configs.size

            volume_configs.each do |vol_config|
              detach_volume(vol_config)
            end
          end

          private

            def collect_volume_configs
              configs = []

              @config.deploy.application.servers.each do |server_name, server_config|
                next unless server_config.volumes && !server_config.volumes.empty?

                resolved_server = @namer.server_name(server_name, 1)

                server_config.volumes.each_key do |vol_name|
                  configs << {
                    name: @namer.server_volume_name(server_name, vol_name),
                    server_name: resolved_server,
                    mount_path: @namer.server_volume_host_path(server_name, vol_name)
                  }
                end
              end

              configs
            end

            def detach_volume(vol_config)
              volume = @provider.get_volume_by_name(vol_config[:name])
              return unless volume&.server_id && !volume.server_id.empty?

              @log.info "Detaching volume: %s", vol_config[:name]

              # Unmount from server before detaching via provider API
              unmount_volume(volume, vol_config[:mount_path])

              @provider.detach_volume(volume.id)
              @log.success "Volume detached: %s", vol_config[:name]
            rescue StandardError => e
              @log.warning "Failed to detach volume %s: %s", vol_config[:name], e.message
            end

            def unmount_volume(volume, mount_path)
              server = @provider.find_server_by_id(volume.server_id)
              return unless server&.public_ipv4

              ssh = External::Ssh.new(server.public_ipv4, @config.ssh_key_path)

              # Check if mounted
              return unless mounted?(ssh, mount_path)

              @log.info "Unmounting volume from %s", mount_path

              # Unmount the volume
              ssh.execute("sudo umount #{mount_path}")

              # Remove from fstab to prevent boot issues
              remove_from_fstab(ssh, mount_path)
            rescue StandardError => e
              @log.warning "Failed to unmount %s: %s", mount_path, e.message
            end

            def mounted?(ssh, mount_path)
              output = ssh.execute("mountpoint -q #{mount_path} && echo 'mounted' || echo 'not_mounted'")
              output.strip == "mounted"
            rescue StandardError
              false
            end

            def remove_from_fstab(ssh, mount_path)
              ssh.execute("sudo sed -i '\\|#{mount_path}|d' /etc/fstab")
            end
        end
      end
    end
  end
end
