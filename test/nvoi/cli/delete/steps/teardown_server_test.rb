# frozen_string_literal: true

require "test_helper"

class TeardownServerStepTest < Minitest::Test
  MockNamer = Struct.new(:app_name) do
    def server_name(group, index)
      "#{app_name}-#{group}-#{index}"
    end
  end

  MockServerConfig = Struct.new(:count, :master, keyword_init: true)
  MockApplication = Struct.new(:servers, keyword_init: true)
  MockDeploy = Struct.new(:application, keyword_init: true)
  MockConfig = Struct.new(:deploy, :namer, keyword_init: true)

  def test_run_deletes_servers
    servers = { "master" => MockServerConfig.new(count: 1, master: true) }
    app = MockApplication.new(servers:)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new("myapp")
    config = MockConfig.new(deploy:, namer:)

    mock_provider = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    server = Nvoi::Objects::Server::Record.new(id: "srv-123", name: "myapp-master-1")

    mock_log.expect(:info, nil, ["Deleting %d server(s) from group '%s'", 1, "master"])
    mock_log.expect(:info, nil, ["Deleting server: %s", "myapp-master-1"])
    mock_provider.expect(:find_server, server, ["myapp-master-1"])
    mock_provider.expect(:delete_server, nil, ["srv-123"])
    mock_log.expect(:success, nil, ["Server deleted: %s", "myapp-master-1"])

    step = Nvoi::Cli::Delete::Steps::TeardownServer.new(config, mock_provider, mock_log)
    step.run

    mock_provider.verify
    mock_log.verify
  end

  def test_run_handles_multiple_servers
    servers = { "workers" => MockServerConfig.new(count: 2, master: false) }
    app = MockApplication.new(servers:)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new("myapp")
    config = MockConfig.new(deploy:, namer:)

    mock_provider = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    server1 = Nvoi::Objects::Server::Record.new(id: "srv-1", name: "myapp-workers-1")
    server2 = Nvoi::Objects::Server::Record.new(id: "srv-2", name: "myapp-workers-2")

    mock_log.expect(:info, nil, ["Deleting %d server(s) from group '%s'", 2, "workers"])
    mock_log.expect(:info, nil, ["Deleting server: %s", "myapp-workers-1"])
    mock_provider.expect(:find_server, server1, ["myapp-workers-1"])
    mock_provider.expect(:delete_server, nil, ["srv-1"])
    mock_log.expect(:success, nil, ["Server deleted: %s", "myapp-workers-1"])
    mock_log.expect(:info, nil, ["Deleting server: %s", "myapp-workers-2"])
    mock_provider.expect(:find_server, server2, ["myapp-workers-2"])
    mock_provider.expect(:delete_server, nil, ["srv-2"])
    mock_log.expect(:success, nil, ["Server deleted: %s", "myapp-workers-2"])

    step = Nvoi::Cli::Delete::Steps::TeardownServer.new(config, mock_provider, mock_log)
    step.run

    mock_provider.verify
    mock_log.verify
  end

  def test_run_does_nothing_when_no_servers
    app = MockApplication.new(servers: {})
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new("myapp")
    config = MockConfig.new(deploy:, namer:)

    mock_provider = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    step = Nvoi::Cli::Delete::Steps::TeardownServer.new(config, mock_provider, mock_log)
    step.run

    # No calls expected
  end
end
