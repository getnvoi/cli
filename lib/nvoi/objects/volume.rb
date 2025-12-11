# frozen_string_literal: true

module Nvoi
  module Objects
    # Volume-related structs
    module Volume
      # Volume represents a block storage volume
      Record = Struct.new(:id, :name, :size, :location, :status, :server_id, :device_path, keyword_init: true)

      # CreateOptions contains options for creating a volume
      CreateOptions = Struct.new(:name, :size, :server_id, :location, keyword_init: true)

      # MountOptions contains options for mounting a volume
      MountOptions = Struct.new(:device_path, :mount_path, :fs_type, keyword_init: true)
    end
  end
end
