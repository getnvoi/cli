# frozen_string_literal: true

module Nvoi
  module External
    # Server-related structs
    module Server
      # Record represents a compute server/instance
      Record = Struct.new(:id, :name, :status, :public_ipv4, :private_ipv4, keyword_init: true)

      # CreateOptions contains options for creating a server
      CreateOptions = Struct.new(:name, :type, :image, :location, :user_data, :network_id, :firewall_id, :ssh_keys, keyword_init: true)
    end

    # Volume-related structs
    module Volume
      # Record represents a block storage volume
      Record = Struct.new(:id, :name, :size, :location, :status, :server_id, :device_path, keyword_init: true)

      # CreateOptions contains options for creating a volume
      CreateOptions = Struct.new(:name, :size, :server_id, :location, keyword_init: true)

      # MountOptions contains options for mounting a volume
      MountOptions = Struct.new(:device_path, :mount_path, :fs_type, keyword_init: true)
    end

    # Network-related structs
    module Network
      # Record represents a virtual network
      Record = Struct.new(:id, :name, :ip_range, keyword_init: true)
    end

    # Firewall-related structs
    module Firewall
      # Record represents a firewall configuration
      Record = Struct.new(:id, :name, keyword_init: true)
    end
  end
end
