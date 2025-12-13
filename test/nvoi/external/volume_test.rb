# frozen_string_literal: true

require "test_helper"

class VolumeTest < Minitest::Test
  def test_volume_struct
    volume = Nvoi::External::Volume::Record.new(
      id: "vol-123",
      name: "myapp-data",
      size: 20,
      location: "fsn1",
      status: "available",
      server_id: "srv-123",
      device_path: "/dev/sdb"
    )

    assert_equal "vol-123", volume.id
    assert_equal "myapp-data", volume.name
    assert_equal 20, volume.size
    assert_equal "fsn1", volume.location
    assert_equal "available", volume.status
    assert_equal "srv-123", volume.server_id
    assert_equal "/dev/sdb", volume.device_path
  end

  def test_volume_create_options_struct
    opts = Nvoi::External::Volume::CreateOptions.new(
      name: "myapp-data",
      size: 20,
      server_id: "srv-123"
    )

    assert_equal "myapp-data", opts.name
    assert_equal 20, opts.size
    assert_equal "srv-123", opts.server_id
  end

  def test_mount_options_struct
    opts = Nvoi::External::Volume::MountOptions.new(
      device_path: "/dev/sdb",
      mount_path: "/mnt/data",
      fs_type: "xfs"
    )

    assert_equal "/dev/sdb", opts.device_path
    assert_equal "/mnt/data", opts.mount_path
    assert_equal "xfs", opts.fs_type
  end
end
