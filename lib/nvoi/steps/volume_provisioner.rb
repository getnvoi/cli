# frozen_string_literal: true

module Nvoi
  module Steps
    # VolumeProvisioner handles provisioning of block storage volumes
    class VolumeProvisioner
      def initialize(config, provider, log)
        @config = config
        @provider = provider
        @log = log
        @namer = config.namer
      end

      def run
        volumes_to_provision = collect_volumes
        return if volumes_to_provision.empty?

        @log.info "Provisioning %d volume(s)", volumes_to_provision.size

        volumes_to_provision.each do |vol_config|
          provision_volume(vol_config)
        end

        @log.success "All volumes provisioned"
      end

      private

        def collect_volumes
          volumes = []

          # Volumes are now defined at server-level
          @config.deploy.application.servers.each do |server_group, server_config|
            next unless server_config.volumes && !server_config.volumes.empty?

            # Resolve to actual server name (e.g., "master" -> "myapp-master-1")
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
          raise VolumeError, "server not found: #{vol_config[:server_name]}" unless server

          # Create volume
          opts = Providers::VolumeCreateOptions.new(
            name: vol_config[:name],
            size: vol_config[:size],
            server_id: server.id
          )
          volume = @provider.create_volume(opts)

          # Attach volume
          @log.info "Attaching volume to server..."
          @provider.attach_volume(volume.id, server.id)

          # Mount volume on server (includes device wait)
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
          ssh = Remote::SSHExecutor.new(server_ip, @config.ssh_key_path)
          volume_manager = Remote::VolumeManager.new(ssh)

          # Get device path (refreshed from provider)
          refreshed = @provider.get_volume(volume.id)
          device_path = refreshed&.device_path

          return unless device_path && !device_path.empty?

          @log.info "Mounting volume at %s", mount_path

          opts = Remote::MountOptions.new(
            device_path:,
            mount_path:,
            fs_type: "xfs"
          )
          volume_manager.mount(opts)
        end
    end
  end
end
