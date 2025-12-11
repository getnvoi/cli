# frozen_string_literal: true

require "test_helper"

class ExecCommandTest < Minitest::Test
  MockNamer = Struct.new(:app_name) do
    def server_name(group, index)
      "#{app_name}-#{group}-#{index}"
    end
  end

  MockServerConfig = Struct.new(:count, :master, keyword_init: true)
  MockAppService = Struct.new(:subdomain, keyword_init: true)
  MockApplication = Struct.new(:name, :servers, :app, keyword_init: true)
  MockDeploy = Struct.new(:application, keyword_init: true)
  MockConfig = Struct.new(:deploy, :namer, :ssh_key_path, :server_name, :container_prefix, :firewall_name, :network_name, :docker_network_name, keyword_init: true)

  def setup
    @mock_log = Minitest::Mock.new
  end

  def test_resolve_server_name_returns_default_server_for_nil
    config = build_config("myapp", "myapp-master-1")
    command = build_command({}, config)

    result = command.send(:resolve_server_name, nil)
    assert_equal "myapp-master-1", result
  end

  def test_resolve_server_name_returns_default_server_for_empty
    config = build_config("myapp", "myapp-master-1")
    command = build_command({}, config)

    result = command.send(:resolve_server_name, "")
    assert_equal "myapp-master-1", result
  end

  def test_resolve_server_name_returns_default_server_for_main
    config = build_config("myapp", "myapp-master-1")
    command = build_command({}, config)

    result = command.send(:resolve_server_name, "main")
    assert_equal "myapp-master-1", result
  end

  def test_resolve_server_name_with_group_and_index
    config = build_config("myapp", "myapp-master-1")
    command = build_command({}, config)

    result = command.send(:resolve_server_name, "worker-2")
    assert_equal "myapp-worker-2", result
  end

  def test_resolve_server_name_with_group_only
    config = build_config("myapp", "myapp-master-1")
    command = build_command({}, config)

    result = command.send(:resolve_server_name, "worker")
    assert_equal "myapp-worker-1", result
  end

  def test_resolve_server_name_with_branched_config
    # Simulate branched app name
    config = build_config("myapp-rel", "myapp-rel-master-1")
    command = build_command({}, config)

    result = command.send(:resolve_server_name, nil)
    assert_equal "myapp-rel-master-1", result
  end

  def test_resolve_server_name_with_branched_config_and_group
    config = build_config("myapp-rel", "myapp-rel-master-1")
    command = build_command({}, config)

    result = command.send(:resolve_server_name, "worker-1")
    assert_equal "myapp-rel-worker-1", result
  end

  def test_get_all_server_names_single_server
    servers = { "master" => MockServerConfig.new(count: 1) }
    config = build_config_with_servers("myapp", servers)
    command = build_command({}, config)

    result = command.send(:get_all_server_names)
    assert_equal ["myapp-master-1"], result
  end

  def test_get_all_server_names_multiple_servers
    servers = {
      "master" => MockServerConfig.new(count: 1),
      "worker" => MockServerConfig.new(count: 2)
    }
    config = build_config_with_servers("myapp", servers)
    command = build_command({}, config)

    result = command.send(:get_all_server_names)
    assert_includes result, "myapp-master-1"
    assert_includes result, "myapp-worker-1"
    assert_includes result, "myapp-worker-2"
    assert_equal 3, result.size
  end

  def test_get_all_server_names_with_branched_config
    servers = { "master" => MockServerConfig.new(count: 1) }
    config = build_config_with_servers("myapp-staging", servers)
    command = build_command({}, config)

    result = command.send(:get_all_server_names)
    assert_equal ["myapp-staging-master-1"], result
  end

  def test_branch_override_applied_to_namer
    servers = { "master" => MockServerConfig.new(count: 1, master: true) }
    services = { "web" => MockAppService.new(subdomain: "www") }
    app = MockApplication.new(name: "myapp", servers: servers, app: services)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new("myapp")
    config = MockConfig.new(
      deploy: deploy,
      namer: namer,
      ssh_key_path: "/tmp/key",
      server_name: "myapp-master-1"
    )

    Nvoi.stub(:logger, @mock_log) do
      command = Nvoi::Cli::Exec::Command.new({ branch: "rel" })
      command.instance_variable_set(:@config, config)

      # Apply branch override manually (normally done in run)
      override = Nvoi::Objects::ConfigOverride.new(branch: "rel")
      override.apply(config)

      # After override, app name should be myapp-rel
      assert_equal "myapp-rel", config.deploy.application.name
      assert_equal "rel-www", config.deploy.application.app["web"].subdomain
      # Server name should be regenerated
      assert_equal "myapp-rel-master-1", config.server_name
    end
  end

  private

  def build_config(app_name, server_name)
    servers = { "master" => MockServerConfig.new(count: 1) }
    app = MockApplication.new(name: app_name, servers: servers)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new(app_name)
    MockConfig.new(deploy: deploy, namer: namer, ssh_key_path: "/tmp/key", server_name: server_name)
  end

  def build_config_with_servers(app_name, servers)
    app = MockApplication.new(name: app_name, servers: servers)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new(app_name)
    MockConfig.new(deploy: deploy, namer: namer, ssh_key_path: "/tmp/key", server_name: "#{app_name}-master-1")
  end

  def build_command(options, config)
    Nvoi.stub(:logger, @mock_log) do
      command = Nvoi::Cli::Exec::Command.new(options)
      command.instance_variable_set(:@config, config)
      command
    end
  end
end
