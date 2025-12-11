# frozen_string_literal: true

require "test_helper"

class DetachVolumesStepTest < Minitest::Test
  MockNamer = Struct.new(:app_name) do
    def server_volume_name(server, vol)
      "#{app_name}-#{server}-#{vol}"
    end

    def server_name(group, _index)
      "#{app_name}-#{group}-1"
    end

    def server_volume_host_path(server, vol)
      "/mnt/#{server}-#{vol}"
    end
  end

  MockServerConfig = Struct.new(:volumes, keyword_init: true)
  MockVolumeConfig = Struct.new(:size, keyword_init: true)
  MockApplication = Struct.new(:servers, keyword_init: true)
  MockDeploy = Struct.new(:application, keyword_init: true)
  MockConfig = Struct.new(:deploy, :namer, :ssh_key_path, keyword_init: true)

  def test_run_detaches_volumes_with_unmount
    volumes = { "data" => MockVolumeConfig.new(size: 20) }
    servers = { "master" => MockServerConfig.new(volumes:) }
    app = MockApplication.new(servers:)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new("myapp")
    config = MockConfig.new(deploy:, namer:, ssh_key_path: "/tmp/key")

    mock_provider = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    volume = Nvoi::Objects::Volume::Record.new(id: "vol-123", name: "myapp-master-data", server_id: "srv-123")
    server = Nvoi::Objects::Server::Record.new(id: "srv-123", name: "myapp-master-1", public_ipv4: "1.2.3.4")

    mock_log.expect(:info, nil, ["Detaching %d volume(s)", 1])
    mock_provider.expect(:get_volume_by_name, volume, ["myapp-master-data"])
    mock_log.expect(:info, nil, ["Detaching volume: %s", "myapp-master-data"])
    mock_provider.expect(:find_server_by_id, server, ["srv-123"])

    # The SSH class will be instantiated and called - we need to stub it
    mock_ssh = Minitest::Mock.new
    mock_ssh.expect(:execute, "mounted", ["mountpoint -q /mnt/master-data && echo 'mounted' || echo 'not_mounted'"])

    # Stub External::Ssh.new to return our mock
    Nvoi::External::Ssh.stub(:new, mock_ssh) do
      mock_log.expect(:info, nil, ["Unmounting volume from %s", "/mnt/master-data"])
      mock_ssh.expect(:execute, "", ["sudo umount /mnt/master-data"])
      mock_ssh.expect(:execute, "", ["sudo sed -i '\\|/mnt/master-data|d' /etc/fstab"])
      mock_provider.expect(:detach_volume, nil, ["vol-123"])
      mock_log.expect(:success, nil, ["Volume detached: %s", "myapp-master-data"])

      step = Nvoi::Cli::Delete::Steps::DetachVolumes.new(config, mock_provider, mock_log)
      step.run
    end

    mock_provider.verify
    mock_log.verify
  end

  def test_run_skips_unmount_when_not_mounted
    volumes = { "data" => MockVolumeConfig.new(size: 20) }
    servers = { "master" => MockServerConfig.new(volumes:) }
    app = MockApplication.new(servers:)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new("myapp")
    config = MockConfig.new(deploy:, namer:, ssh_key_path: "/tmp/key")

    mock_provider = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    volume = Nvoi::Objects::Volume::Record.new(id: "vol-123", name: "myapp-master-data", server_id: "srv-123")
    server = Nvoi::Objects::Server::Record.new(id: "srv-123", name: "myapp-master-1", public_ipv4: "1.2.3.4")

    mock_log.expect(:info, nil, ["Detaching %d volume(s)", 1])
    mock_provider.expect(:get_volume_by_name, volume, ["myapp-master-data"])
    mock_log.expect(:info, nil, ["Detaching volume: %s", "myapp-master-data"])
    mock_provider.expect(:find_server_by_id, server, ["srv-123"])

    mock_ssh = Minitest::Mock.new
    mock_ssh.expect(:execute, "not_mounted", ["mountpoint -q /mnt/master-data && echo 'mounted' || echo 'not_mounted'"])

    Nvoi::External::Ssh.stub(:new, mock_ssh) do
      # No unmount calls expected since not mounted
      mock_provider.expect(:detach_volume, nil, ["vol-123"])
      mock_log.expect(:success, nil, ["Volume detached: %s", "myapp-master-data"])

      step = Nvoi::Cli::Delete::Steps::DetachVolumes.new(config, mock_provider, mock_log)
      step.run
    end

    mock_provider.verify
    mock_log.verify
  end

  def test_run_skips_unattached_volumes
    volumes = { "data" => MockVolumeConfig.new(size: 20) }
    servers = { "master" => MockServerConfig.new(volumes:) }
    app = MockApplication.new(servers:)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new("myapp")
    config = MockConfig.new(deploy:, namer:, ssh_key_path: "/tmp/key")

    mock_provider = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    # Volume with no server_id
    volume = Nvoi::Objects::Volume::Record.new(id: "vol-123", name: "myapp-master-data", server_id: nil)

    mock_log.expect(:info, nil, ["Detaching %d volume(s)", 1])
    mock_provider.expect(:get_volume_by_name, volume, ["myapp-master-data"])

    step = Nvoi::Cli::Delete::Steps::DetachVolumes.new(config, mock_provider, mock_log)
    step.run

    mock_provider.verify
    mock_log.verify
  end

  def test_run_does_nothing_when_no_volumes
    servers = { "master" => MockServerConfig.new(volumes: {}) }
    app = MockApplication.new(servers:)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new("myapp")
    config = MockConfig.new(deploy:, namer:, ssh_key_path: "/tmp/key")

    mock_provider = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    step = Nvoi::Cli::Delete::Steps::DetachVolumes.new(config, mock_provider, mock_log)
    step.run

    # No calls expected
  end

  def test_unmount_handles_ssh_errors_gracefully_in_mounted_check
    volumes = { "data" => MockVolumeConfig.new(size: 20) }
    servers = { "master" => MockServerConfig.new(volumes:) }
    app = MockApplication.new(servers:)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new("myapp")
    config = MockConfig.new(deploy:, namer:, ssh_key_path: "/tmp/key")

    mock_provider = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    volume = Nvoi::Objects::Volume::Record.new(id: "vol-123", name: "myapp-master-data", server_id: "srv-123")
    server = Nvoi::Objects::Server::Record.new(id: "srv-123", name: "myapp-master-1", public_ipv4: "1.2.3.4")

    mock_log.expect(:info, nil, ["Detaching %d volume(s)", 1])
    mock_provider.expect(:get_volume_by_name, volume, ["myapp-master-data"])
    mock_log.expect(:info, nil, ["Detaching volume: %s", "myapp-master-data"])
    mock_provider.expect(:find_server_by_id, server, ["srv-123"])

    # SSH fails on mounted? check - returns false, skips unmount
    ssh_that_fails = Object.new
    def ssh_that_fails.execute(_cmd)
      raise StandardError, "SSH connection failed"
    end

    Nvoi::External::Ssh.stub(:new, ssh_that_fails) do
      # mounted? catches error and returns false, so no unmount attempted
      # Detach still happens via provider API
      mock_provider.expect(:detach_volume, nil, ["vol-123"])
      mock_log.expect(:success, nil, ["Volume detached: %s", "myapp-master-data"])

      step = Nvoi::Cli::Delete::Steps::DetachVolumes.new(config, mock_provider, mock_log)
      step.run
    end

    mock_provider.verify
    mock_log.verify
  end

  def test_unmount_logs_warning_when_umount_fails
    volumes = { "data" => MockVolumeConfig.new(size: 20) }
    servers = { "master" => MockServerConfig.new(volumes:) }
    app = MockApplication.new(servers:)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new("myapp")
    config = MockConfig.new(deploy:, namer:, ssh_key_path: "/tmp/key")

    mock_provider = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    volume = Nvoi::Objects::Volume::Record.new(id: "vol-123", name: "myapp-master-data", server_id: "srv-123")
    server = Nvoi::Objects::Server::Record.new(id: "srv-123", name: "myapp-master-1", public_ipv4: "1.2.3.4")

    mock_log.expect(:info, nil, ["Detaching %d volume(s)", 1])
    mock_provider.expect(:get_volume_by_name, volume, ["myapp-master-data"])
    mock_log.expect(:info, nil, ["Detaching volume: %s", "myapp-master-data"])
    mock_provider.expect(:find_server_by_id, server, ["srv-123"])

    # SSH succeeds for mounted? check, but fails on umount
    call_count = 0
    ssh_fails_on_umount = Object.new
    ssh_fails_on_umount.define_singleton_method(:execute) do |cmd|
      call_count += 1
      if cmd.include?("mountpoint")
        "mounted"
      else
        raise StandardError, "umount failed: device busy"
      end
    end

    Nvoi::External::Ssh.stub(:new, ssh_fails_on_umount) do
      mock_log.expect(:info, nil, ["Unmounting volume from %s", "/mnt/master-data"])
      mock_log.expect(:warning, nil, ["Failed to unmount %s: %s", "/mnt/master-data", "umount failed: device busy"])
      mock_provider.expect(:detach_volume, nil, ["vol-123"])
      mock_log.expect(:success, nil, ["Volume detached: %s", "myapp-master-data"])

      step = Nvoi::Cli::Delete::Steps::DetachVolumes.new(config, mock_provider, mock_log)
      step.run
    end

    mock_provider.verify
    mock_log.verify
  end
end
