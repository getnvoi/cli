# frozen_string_literal: true

module Nvoi
  module Remote
    # MountOptions contains options for mounting a volume
    MountOptions = Struct.new(:device_path, :mount_path, :fs_type, keyword_init: true)

    # VolumeManager handles volume mount operations via SSH
    class VolumeManager
      def initialize(ssh)
        @ssh = ssh
      end

      # Mount formats (if needed) and mounts a volume at the specified path
      def mount(opts)
        fs_type = opts.fs_type || "xfs"

        # Check if already mounted
        return if mounted?(opts.mount_path)

        # Check if device has a filesystem
        unless has_filesystem?(opts.device_path)
          format_volume(opts.device_path, fs_type)
        end

        # Create mount point
        @ssh.execute("sudo mkdir -p #{opts.mount_path}")

        # Mount the volume
        @ssh.execute("sudo mount #{opts.device_path} #{opts.mount_path}")

        # Add to fstab for persistence
        add_to_fstab(opts.device_path, opts.mount_path, fs_type)
      end

      # Unmount a volume
      def unmount(mount_path)
        return unless mounted?(mount_path)

        @ssh.execute("sudo umount #{mount_path}")
      end

      # Check if a path is currently mounted
      def mounted?(mount_path)
        output = @ssh.execute("mountpoint -q #{mount_path} && echo 'mounted' || echo 'not_mounted'")
        output.strip == "mounted"
      rescue SSHCommandError
        # mountpoint command might fail if path doesn't exist
        false
      end

      # Remove a mount entry from /etc/fstab
      def remove_from_fstab(mount_path)
        @ssh.execute("sudo sed -i '\\|#{mount_path}|d' /etc/fstab")
      end

      private

        def has_filesystem?(device_path)
          output = @ssh.execute("sudo blkid #{device_path}")
          output.include?("TYPE=")
        rescue SSHCommandError
          # blkid returns error if no filesystem
          false
        end

        def format_volume(device_path, fs_type)
          @ssh.execute("sudo mkfs.#{fs_type} #{device_path}")
        end

        def add_to_fstab(device_path, mount_path, fs_type)
          # Check if entry already exists
          output = @ssh.execute("grep -q '#{mount_path}' /etc/fstab && echo 'exists' || echo 'missing'")
          return if output.strip == "exists"

          # Add fstab entry using UUID for reliability
          cmd = "UUID=$(sudo blkid -s UUID -o value #{device_path}) && " \
                "echo \"UUID=$UUID #{mount_path} #{fs_type} defaults,nofail 0 2\" | sudo tee -a /etc/fstab"
          @ssh.execute(cmd)
        end
    end
  end
end
