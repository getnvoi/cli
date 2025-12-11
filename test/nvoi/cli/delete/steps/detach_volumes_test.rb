# frozen_string_literal: true

require "test_helper"
require_relative "../../../../../lib/nvoi/cli/delete/steps/detach_volumes"

class DetachVolumesStepTest < Minitest::Test
  MockNamer = Struct.new(:app_name) do
    def server_volume_name(server, vol)
      "#{app_name}-#{server}-#{vol}"
    end
  end

  MockServerConfig = Struct.new(:volumes, keyword_init: true)
  MockVolumeConfig = Struct.new(:size, keyword_init: true)
  MockApplication = Struct.new(:servers, keyword_init: true)
  MockDeploy = Struct.new(:application, keyword_init: true)
  MockConfig = Struct.new(:deploy, :namer, keyword_init: true)

  def test_run_detaches_volumes
    volumes = { "data" => MockVolumeConfig.new(size: 20) }
    servers = { "master" => MockServerConfig.new(volumes: volumes) }
    app = MockApplication.new(servers: servers)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new("myapp")
    config = MockConfig.new(deploy: deploy, namer: namer)

    mock_provider = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    volume = Nvoi::Objects::Volume.new(id: "vol-123", name: "myapp-master-data", server_id: "srv-123")

    mock_log.expect(:info, nil, ["Detaching %d volume(s)", 1])
    mock_provider.expect(:get_volume_by_name, volume, ["myapp-master-data"])
    mock_log.expect(:info, nil, ["Detaching volume: %s", "myapp-master-data"])
    mock_provider.expect(:detach_volume, nil, ["vol-123"])
    mock_log.expect(:success, nil, ["Volume detached: %s", "myapp-master-data"])

    step = Nvoi::Cli::Delete::Steps::DetachVolumes.new(config, mock_provider, mock_log)
    step.run

    mock_provider.verify
    mock_log.verify
  end

  def test_run_skips_unattached_volumes
    volumes = { "data" => MockVolumeConfig.new(size: 20) }
    servers = { "master" => MockServerConfig.new(volumes: volumes) }
    app = MockApplication.new(servers: servers)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new("myapp")
    config = MockConfig.new(deploy: deploy, namer: namer)

    mock_provider = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    # Volume with no server_id
    volume = Nvoi::Objects::Volume.new(id: "vol-123", name: "myapp-master-data", server_id: nil)

    mock_log.expect(:info, nil, ["Detaching %d volume(s)", 1])
    mock_provider.expect(:get_volume_by_name, volume, ["myapp-master-data"])

    step = Nvoi::Cli::Delete::Steps::DetachVolumes.new(config, mock_provider, mock_log)
    step.run

    mock_provider.verify
    mock_log.verify
  end

  def test_run_does_nothing_when_no_volumes
    servers = { "master" => MockServerConfig.new(volumes: {}) }
    app = MockApplication.new(servers: servers)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new("myapp")
    config = MockConfig.new(deploy: deploy, namer: namer)

    mock_provider = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    step = Nvoi::Cli::Delete::Steps::DetachVolumes.new(config, mock_provider, mock_log)
    step.run

    # No calls expected
  end
end
