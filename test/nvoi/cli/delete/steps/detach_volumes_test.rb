# frozen_string_literal: true

require "test_helper"

class DetachVolumesTest < Minitest::Test
  MockConfig = Struct.new(:deploy, :namer, :ssh_key_path, keyword_init: true)
  MockDeploy = Struct.new(:application, keyword_init: true)
  MockApplication = Struct.new(:servers, keyword_init: true)
  MockServerConfig = Struct.new(:volumes, keyword_init: true)
  MockNamer = Struct.new(:app_name, keyword_init: true) do
    def server_name(name, index)
      "#{app_name}-#{name}-#{index}"
    end
    def server_volume_name(server_name, volume_name)
      "#{app_name}-#{server_name}-#{volume_name}"
    end
    def server_volume_host_path(server_name, volume_name)
      "/opt/nvoi/volumes/#{app_name}-#{server_name}-#{volume_name}"
    end
  end
  MockVolume = Struct.new(:id, :server_id, keyword_init: true)

  def setup
    @log = Minitest::Mock.new
    @provider = Minitest::Mock.new
  end

  def test_run_skips_when_no_volumes
    servers = { "master" => MockServerConfig.new(volumes: {}) }
    app = MockApplication.new(servers:)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new(app_name: "myapp")
    config = MockConfig.new(deploy:, namer:, ssh_key_path: "/tmp/key")

    step = Nvoi::Cli::Delete::Steps::DetachVolumes.new(config, @provider, @log)
    step.run

    # Nothing called
  end

  def test_run_skips_unattached_volumes
    servers = {
      "master" => MockServerConfig.new(volumes: { "data" => { "size" => 50 } })
    }
    app = MockApplication.new(servers:)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new(app_name: "myapp")
    config = MockConfig.new(deploy:, namer:, ssh_key_path: "/tmp/key")

    @log.expect(:info, nil, ["Detaching %d volume(s)", 1])
    @provider.expect(:get_volume_by_name, MockVolume.new(id: "vol-1", server_id: nil), ["myapp-master-data"])

    step = Nvoi::Cli::Delete::Steps::DetachVolumes.new(config, @provider, @log)
    step.run

    @provider.verify
    @log.verify
  end

  def test_run_handles_volume_not_found
    servers = {
      "master" => MockServerConfig.new(volumes: { "data" => { "size" => 50 } })
    }
    app = MockApplication.new(servers:)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new(app_name: "myapp")
    config = MockConfig.new(deploy:, namer:, ssh_key_path: "/tmp/key")

    @log.expect(:info, nil, ["Detaching %d volume(s)", 1])
    @provider.expect(:get_volume_by_name, nil, ["myapp-master-data"])

    step = Nvoi::Cli::Delete::Steps::DetachVolumes.new(config, @provider, @log)
    step.run

    @provider.verify
    @log.verify
  end
end
