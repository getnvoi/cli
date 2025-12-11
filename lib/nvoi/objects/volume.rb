# frozen_string_literal: true

module Nvoi
  module Objects
    # Volume represents a block storage volume
    Volume = Struct.new(:id, :name, :size, :location, :status, :server_id, :device_path, keyword_init: true)

    # VolumeCreateOptions contains options for creating a volume
    VolumeCreateOptions = Struct.new(:name, :size, :server_id, keyword_init: true)

    # MountOptions contains options for mounting a volume
    MountOptions = Struct.new(:device_path, :mount_path, :fs_type, keyword_init: true)
  end
end
