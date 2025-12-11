# frozen_string_literal: true

module Nvoi
  class Cli
    module Deploy
      module Steps
        # ProvisionVolume handles block storage volume provisioning
        class ProvisionVolume
          def initialize(config, provider, log)
            @config = config
            @provider = provider
            @log = log
            @namer = config.namer
          end

          def run
            volumes = collect_volumes
            return if volumes.empty?

            @log.info "Provisioning %d volume(s)", volumes.size

            volumes.each do |vol_config|
              provision_volume(vol_config)
            end

            @log.success "All volumes provisioned"
          end

          private

            def collect_volumes
              volumes = []

              @config.deploy.application.servers.each do |server_group, server_config|
                next unless server_config.volumes && !server_config.volumes.empty?

                resolved_server = @namer.server_name(server_group, 1)

                server_config.volumes.each do |vol_name, vol_config|
                  full_name = @namer.server_volume_name(server_group, vol_name)
                  volumes << {
                    name: full_name,
                    server_name: resolved_server,
                    mount_path: @namer.server_volume_host_path(server_group, vol_name),
                    size: vol_config.size
                  }
                end
              end

              volumes
            end

            def provision_volume(vol_config)
              @log.info "Provisioning volume: %s", vol_config[:name]

              # Check if volume already exists
              existing = @provider.get_volume_by_name(vol_config[:name])
              if existing
                @log.info "Volume already exists: %s", vol_config[:name]
                ensure_attached_and_mounted(existing, vol_config)
                return
              end

              # Find server to attach to
              server = @provider.find_server(vol_config[:server_name])
              raise Errors::VolumeError, "server not found: #{vol_config[:server_name]}" unless server

              # Create volume
              opts = Objects::Volume::CreateOptions.new(
                name: vol_config[:name],
                size: vol_config[:size],
                server_id: server.id
              )
              volume = @provider.create_volume(opts)

              # Attach volume
              @log.info "Attaching volume to server..."
              @provider.attach_volume(volume.id, server.id)

              # Mount volume on server
              mount_volume(server.public_ipv4, volume, vol_config[:mount_path])

              @log.success "Volume provisioned and mounted: %s", vol_config[:name]
            end

            def ensure_attached_and_mounted(volume, vol_config)
              server = @provider.find_server(vol_config[:server_name])
              return unless server

              # Attach if not attached
              if volume.server_id.nil? || volume.server_id.empty?
                @log.info "Attaching existing volume..."
                @provider.attach_volume(volume.id, server.id)
                volume = @provider.get_volume(volume.id)
              end

              # Mount if not mounted
              mount_volume(server.public_ipv4, volume, vol_config[:mount_path])
            end

            def mount_volume(server_ip, volume, mount_path)
              ssh = External::Ssh.new(server_ip, @config.ssh_key_path)

              # Get device path (refreshed from provider)
              refreshed = @provider.get_volume(volume.id)
              device_path = refreshed&.device_path

              return unless device_path && !device_path.empty?

              @log.info "Mounting volume at %s", mount_path

              # Wait for device to be available
              wait_for_device(ssh, device_path)

              # Check if already mounted
              mount_check = ssh.execute("mount | grep #{device_path} || true")
              if mount_check.include?(mount_path)
                @log.info "Volume already mounted at %s", mount_path
                return
              end

              # Create mount point
              ssh.execute("sudo mkdir -p #{mount_path}")

              # Check if device has filesystem
              fs_check = ssh.execute("sudo blkid #{device_path} || true")
              if fs_check.empty? || !fs_check.include?("TYPE=")
                # Format with XFS
                @log.info "Formatting volume with XFS"
                ssh.execute("sudo mkfs.xfs #{device_path}")
              end

              # Mount
              ssh.execute("sudo mount #{device_path} #{mount_path}")

              # Add to fstab using UUID (more reliable than device path)
              fstab_check = ssh.execute("grep '#{mount_path}' /etc/fstab || true")
              if fstab_check.empty?
                cmd = "UUID=$(sudo blkid -s UUID -o value #{device_path}) && " \
                      "echo \"UUID=$UUID #{mount_path} xfs defaults,nofail 0 2\" | sudo tee -a /etc/fstab"
                ssh.execute(cmd)
              end

              @log.success "Volume mounted at %s", mount_path
            end

            def wait_for_device(ssh, device_path)
              30.times do
                check = ssh.execute("test -b #{device_path} && echo 'ready' || true")
                return if check.strip == "ready"

                sleep(2)
              end

              raise Errors::VolumeError, "device not available: #{device_path}"
            end
        end
      end
    end
  end
end
