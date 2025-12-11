# frozen_string_literal: true

require "test_helper"

class SetupK3sStepTest < Minitest::Test
  def setup
    @mock_ssh = Minitest::Mock.new
    @mock_log = Minitest::Mock.new
    @mock_provider = Minitest::Mock.new
  end

  def test_deploy_error_backend_applies_manifest
    mock_config = mock_config_for_test
    step = Nvoi::Cli::Deploy::Steps::SetupK3s.new(mock_config, @mock_provider, @mock_log, "1.2.3.4")

    @mock_log.expect(:info, nil, ["Deploying custom error backend"])
    @mock_ssh.expect(:execute, "", [String]) # apply_manifest call
    @mock_ssh.expect(:execute, "1", [/kubectl get deployment nvoi-error-backend/])
    @mock_log.expect(:success, nil, ["Error backend is ready"])

    step.send(:deploy_error_backend, @mock_ssh)

    @mock_ssh.verify
    @mock_log.verify
  end

  def test_deploy_error_backend_retries_until_ready
    mock_config = mock_config_for_test
    step = Nvoi::Cli::Deploy::Steps::SetupK3s.new(mock_config, @mock_provider, @mock_log, "1.2.3.4")

    @mock_log.expect(:info, nil, ["Deploying custom error backend"])
    @mock_ssh.expect(:execute, "", [String]) # apply_manifest call

    # First two attempts return not ready
    @mock_ssh.expect(:execute, "0", [/kubectl get deployment nvoi-error-backend/])
    @mock_ssh.expect(:execute, "", [/kubectl get deployment nvoi-error-backend/])
    # Third attempt ready
    @mock_ssh.expect(:execute, "1", [/kubectl get deployment nvoi-error-backend/])
    @mock_log.expect(:success, nil, ["Error backend is ready"])

    step.send(:deploy_error_backend, @mock_ssh)

    @mock_ssh.verify
    @mock_log.verify
  end

  def test_deploy_error_backend_raises_after_timeout
    mock_config = mock_config_for_test
    step = Nvoi::Cli::Deploy::Steps::SetupK3s.new(mock_config, @mock_provider, @mock_log, "1.2.3.4")

    @mock_log.expect(:info, nil, ["Deploying custom error backend"])
    @mock_ssh.expect(:execute, "", [String]) # apply_manifest call

    # All 30 attempts return not ready
    30.times do
      @mock_ssh.expect(:execute, "0", [/kubectl get deployment nvoi-error-backend/])
    end

    error = assert_raises(Nvoi::Errors::K8sError) do
      step.send(:deploy_error_backend, @mock_ssh)
    end
    assert_match(/Error backend failed to become ready/, error.message)
  end

  def test_setup_kubeconfig_uses_provided_private_ip
    mock_config = mock_config_for_test
    step = Nvoi::Cli::Deploy::Steps::SetupK3s.new(mock_config, @mock_provider, @mock_log, "1.2.3.4")

    # Expect the command to use the provided private IP
    @mock_ssh.expect(:execute, "", [/sed -i "s\/127\.0\.0\.1\/10\.0\.0\.5\/g"/])

    step.send(:setup_kubeconfig, @mock_ssh, "10.0.0.5")

    @mock_ssh.verify
  end

  def test_setup_kubeconfig_discovers_private_ip_when_not_provided
    mock_config = mock_config_for_test
    step = Nvoi::Cli::Deploy::Steps::SetupK3s.new(mock_config, @mock_provider, @mock_log, "1.2.3.4")

    # First call discovers private IP
    @mock_ssh.expect(:execute, "172.16.0.2\n", [/ip addr show.*grep -E 'inet \(10/])
    # Second call is the kubeconfig setup using discovered IP
    @mock_ssh.expect(:execute, "", [/sed -i "s\/127\.0\.0\.1\/172\.16\.0\.2\/g"/])

    step.send(:setup_kubeconfig, @mock_ssh, nil)

    @mock_ssh.verify
  end

  def test_discover_private_ip_returns_ip
    mock_config = mock_config_for_test
    step = Nvoi::Cli::Deploy::Steps::SetupK3s.new(mock_config, @mock_provider, @mock_log, "1.2.3.4")

    @mock_ssh.expect(:execute, "172.16.0.2\n", [/ip addr show.*grep -E 'inet \(10/])

    result = step.send(:discover_private_ip, @mock_ssh)

    assert_equal "172.16.0.2", result
    @mock_ssh.verify
  end

  def test_discover_private_ip_returns_nil_when_empty
    mock_config = mock_config_for_test
    step = Nvoi::Cli::Deploy::Steps::SetupK3s.new(mock_config, @mock_provider, @mock_log, "1.2.3.4")

    @mock_ssh.expect(:execute, "\n", [/ip addr show.*grep -E 'inet \(10/])

    result = step.send(:discover_private_ip, @mock_ssh)

    assert_nil result
    @mock_ssh.verify
  end

  private

  MockNamer = Struct.new(:app_name) do
    def server_name(group, index)
      "#{app_name}-#{group}-#{index}"
    end
  end

  MockServerConfig = Struct.new(:type, :location, :count, :master, keyword_init: true)
  MockApplication = Struct.new(:servers, keyword_init: true)
  MockDeploy = Struct.new(:application, keyword_init: true)
  MockConfig = Struct.new(:deploy, :namer, :ssh_key_path, :provider_name, keyword_init: true)

  def mock_config_for_test
    servers = { "master" => MockServerConfig.new(type: "DEV1-S", location: "fr-par-1", count: 1, master: true) }
    app = MockApplication.new(servers: servers)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new("testapp")
    MockConfig.new(deploy: deploy, namer: namer, ssh_key_path: "/tmp/key", provider_name: "scaleway")
  end
end
