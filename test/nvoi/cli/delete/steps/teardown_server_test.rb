# frozen_string_literal: true

require "test_helper"

class TeardownServerTest < Minitest::Test
  MockConfig = Struct.new(:deploy, :namer, keyword_init: true)
  MockDeploy = Struct.new(:application, keyword_init: true)
  MockApplication = Struct.new(:servers, keyword_init: true)
  MockServerConfig = Struct.new(:count, keyword_init: true)
  MockNamer = Struct.new(:app_name, keyword_init: true) do
    def server_name(group, index)
      "#{app_name}-#{group}-#{index}"
    end
  end
  MockServer = Struct.new(:id, :public_ipv4, keyword_init: true)

  def setup
    @log = Minitest::Mock.new
    @provider = Minitest::Mock.new
  end

  def test_run_deletes_servers_in_each_group
    servers = {
      "master" => MockServerConfig.new(count: 1),
      "worker" => MockServerConfig.new(count: 2)
    }
    app = MockApplication.new(servers:)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new(app_name: "myapp")
    config = MockConfig.new(deploy:, namer:)

    @log.expect(:info, nil, ["Deleting %d server(s) from group '%s'", 1, "master"])
    @log.expect(:info, nil, ["Deleting server: %s", "myapp-master-1"])
    @provider.expect(:find_server, MockServer.new(id: "srv-1"), ["myapp-master-1"])
    @provider.expect(:delete_server, nil, ["srv-1"])
    @log.expect(:success, nil, ["Server deleted: %s", "myapp-master-1"])

    @log.expect(:info, nil, ["Deleting %d server(s) from group '%s'", 2, "worker"])
    @log.expect(:info, nil, ["Deleting server: %s", "myapp-worker-1"])
    @provider.expect(:find_server, MockServer.new(id: "srv-2"), ["myapp-worker-1"])
    @provider.expect(:delete_server, nil, ["srv-2"])
    @log.expect(:success, nil, ["Server deleted: %s", "myapp-worker-1"])

    @log.expect(:info, nil, ["Deleting server: %s", "myapp-worker-2"])
    @provider.expect(:find_server, MockServer.new(id: "srv-3"), ["myapp-worker-2"])
    @provider.expect(:delete_server, nil, ["srv-3"])
    @log.expect(:success, nil, ["Server deleted: %s", "myapp-worker-2"])

    step = Nvoi::Cli::Delete::Steps::TeardownServer.new(config, @provider, @log)
    step.run

    @provider.verify
    @log.verify
  end

  def test_run_skips_when_no_servers
    app = MockApplication.new(servers: {})
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new(app_name: "myapp")
    config = MockConfig.new(deploy:, namer:)

    step = Nvoi::Cli::Delete::Steps::TeardownServer.new(config, @provider, @log)
    step.run

    # No expectations - nothing should be called
  end

  def test_run_handles_server_not_found
    servers = { "master" => MockServerConfig.new(count: 1) }
    app = MockApplication.new(servers:)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new(app_name: "myapp")
    config = MockConfig.new(deploy:, namer:)

    @log.expect(:info, nil, ["Deleting %d server(s) from group '%s'", 1, "master"])
    @log.expect(:info, nil, ["Deleting server: %s", "myapp-master-1"])
    @provider.expect(:find_server, nil, ["myapp-master-1"])

    step = Nvoi::Cli::Delete::Steps::TeardownServer.new(config, @provider, @log)
    step.run

    @provider.verify
    @log.verify
  end

  def test_run_handles_delete_error_gracefully
    servers = { "master" => MockServerConfig.new(count: 1) }
    app = MockApplication.new(servers:)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new(app_name: "myapp")
    config = MockConfig.new(deploy:, namer:)

    @log.expect(:info, nil, ["Deleting %d server(s) from group '%s'", 1, "master"])
    @log.expect(:info, nil, ["Deleting server: %s", "myapp-master-1"])
    @provider.expect(:find_server, MockServer.new(id: "srv-1"), ["myapp-master-1"])
    @provider.expect(:delete_server, nil) { raise "API error" }
    @log.expect(:warning, nil, ["Failed to delete server %s: %s", "myapp-master-1", "API error"])

    step = Nvoi::Cli::Delete::Steps::TeardownServer.new(config, @provider, @log)
    step.run

    @log.verify
  end
end
