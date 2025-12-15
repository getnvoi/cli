# frozen_string_literal: true

require "test_helper"

class TeardownVolumeTest < Minitest::Test
  MockConfig = Struct.new(:deploy, :namer, keyword_init: true)
  MockDeploy = Struct.new(:application, keyword_init: true)
  MockApplication = Struct.new(:servers, keyword_init: true)
  MockServerConfig = Struct.new(:volumes, keyword_init: true)
  MockNamer = Struct.new(:app_name, keyword_init: true) do
    def server_volume_name(server_name, volume_name)
      "#{app_name}-#{server_name}-#{volume_name}"
    end
  end
  MockVolume = Struct.new(:id, keyword_init: true)

  def setup
    @log = Minitest::Mock.new
    @provider = Minitest::Mock.new
  end

  def test_run_deletes_volumes
    servers = {
      "master" => MockServerConfig.new(volumes: { "data" => { "size" => 50 } })
    }
    app = MockApplication.new(servers:)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new(app_name: "myapp")
    config = MockConfig.new(deploy:, namer:)

    @log.expect(:info, nil, ["Deleting %d volume(s)", 1])
    @log.expect(:info, nil, ["Deleting volume: %s", "myapp-master-data"])
    @provider.expect(:get_volume_by_name, MockVolume.new(id: "vol-123"), ["myapp-master-data"])
    @provider.expect(:delete_volume, nil, ["vol-123"])
    @log.expect(:success, nil, ["Volume deleted: %s", "myapp-master-data"])

    step = Nvoi::Cli::Delete::Steps::TeardownVolume.new(config, @provider, @log)
    step.run

    @provider.verify
    @log.verify
  end

  def test_run_skips_when_no_volumes
    servers = { "master" => MockServerConfig.new(volumes: {}) }
    app = MockApplication.new(servers:)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new(app_name: "myapp")
    config = MockConfig.new(deploy:, namer:)

    step = Nvoi::Cli::Delete::Steps::TeardownVolume.new(config, @provider, @log)
    step.run

    # Nothing called since no volumes
  end

  def test_run_handles_volume_not_found
    servers = {
      "master" => MockServerConfig.new(volumes: { "data" => { "size" => 50 } })
    }
    app = MockApplication.new(servers:)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new(app_name: "myapp")
    config = MockConfig.new(deploy:, namer:)

    @log.expect(:info, nil, ["Deleting %d volume(s)", 1])
    @log.expect(:info, nil, ["Deleting volume: %s", "myapp-master-data"])
    @provider.expect(:get_volume_by_name, nil, ["myapp-master-data"])
    @log.expect(:info, nil, ["Volume not found: %s", "myapp-master-data"])

    step = Nvoi::Cli::Delete::Steps::TeardownVolume.new(config, @provider, @log)
    step.run

    @provider.verify
    @log.verify
  end
end
