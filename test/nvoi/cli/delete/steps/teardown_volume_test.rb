# frozen_string_literal: true

require "test_helper"

class TeardownVolumeStepTest < Minitest::Test
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

  def test_run_deletes_volumes
    volumes = { "data" => MockVolumeConfig.new(size: 20) }
    servers = { "master" => MockServerConfig.new(volumes:) }
    app = MockApplication.new(servers:)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new("myapp")
    config = MockConfig.new(deploy:, namer:)

    mock_provider = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    volume = Nvoi::Objects::Volume::Record.new(id: "vol-123", name: "myapp-master-data")

    mock_log.expect(:info, nil, ["Deleting %d volume(s)", 1])
    mock_log.expect(:info, nil, ["Deleting volume: %s", "myapp-master-data"])
    mock_provider.expect(:get_volume_by_name, volume, ["myapp-master-data"])
    mock_provider.expect(:delete_volume, nil, ["vol-123"])
    mock_log.expect(:success, nil, ["Volume deleted: %s", "myapp-master-data"])

    step = Nvoi::Cli::Delete::Steps::TeardownVolume.new(config, mock_provider, mock_log)
    step.run

    mock_provider.verify
    mock_log.verify
  end

  def test_run_handles_missing_volume
    volumes = { "data" => MockVolumeConfig.new(size: 20) }
    servers = { "master" => MockServerConfig.new(volumes:) }
    app = MockApplication.new(servers:)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new("myapp")
    config = MockConfig.new(deploy:, namer:)

    mock_provider = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    mock_log.expect(:info, nil, ["Deleting %d volume(s)", 1])
    mock_log.expect(:info, nil, ["Deleting volume: %s", "myapp-master-data"])
    mock_provider.expect(:get_volume_by_name, nil, ["myapp-master-data"])
    mock_log.expect(:info, nil, ["Volume not found: %s", "myapp-master-data"])

    step = Nvoi::Cli::Delete::Steps::TeardownVolume.new(config, mock_provider, mock_log)
    step.run

    mock_provider.verify
    mock_log.verify
  end
end
