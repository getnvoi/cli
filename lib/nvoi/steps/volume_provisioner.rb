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

        # Database volume
        db = @config.deploy.application.database
        if db&.volume && !db.volume.empty?
          server_name = resolve_server_name(db.servers)
          volumes << {
            name: @namer.database_volume_name,
            server_name: server_name,
            mount_path: "/opt/nvoi/volumes/#{@namer.database_volume_name}",
            size: 10
          }
        end

        # Service volumes
        @config.deploy.application.services.each do |svc_name, svc|
          next unless svc&.volume && !svc.volume.empty?

          server_name = resolve_server_name(svc.servers)
          vol_name = @namer.service_volume_name(svc_name, "data")
          volumes << {
            name: vol_name,
            server_name: server_name,
            mount_path: "/opt/nvoi/volumes/#{vol_name}",
            size: 10
          }
        end

        # App volumes
        @config.deploy.application.app.each do |app_name, app|
          next unless app&.volumes && !app.volumes.empty?

          server_name = resolve_server_name(app.servers)
          app.volumes.each_key do |vol_key|
            vol_name = @namer.app_volume_name(app_name, vol_key)
            volumes << {
              name: vol_name,
              server_name: server_name,
              mount_path: "/opt/nvoi/volumes/#{vol_name}",
              size: 10
            }
          end
        end

        volumes
      end

      def resolve_server_name(servers)
        return @config.server_name if servers.nil? || servers.empty?

        # Use first server in the list
        group_name = servers.first
        @namer.server_name(group_name, 1)
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

        # Wait for attachment
        sleep(5)

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
          sleep(5)
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
          device_path: device_path,
          mount_path: mount_path,
          fs_type: "xfs"
        )
        volume_manager.mount(opts)
      end
    end
  end
end
