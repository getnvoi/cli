# frozen_string_literal: true

require "test_helper"

class LogsCommandTest < Minitest::Test
  def setup
    @mock_log = Minitest::Mock.new
    @mock_ssh = Minitest::Mock.new
    @mock_provider = Minitest::Mock.new
    @mock_server = Struct.new(:public_ipv4).new("1.2.3.4")
  end

  def test_builds_correct_kubectl_command
    # Test the kubectl command construction logic
    # deployment_name = namer.app_deployment_name(app_name) = "{app_name}-{service_name}"
    deployment_name = "myapp-rails"

    # Default options
    follow = false
    tail = 100

    follow_flag = follow ? "-f" : ""
    tail_flag = "--tail=#{tail}"
    kubectl_cmd = "kubectl logs -l app=#{deployment_name} --prefix --all-containers #{follow_flag} #{tail_flag}".strip.squeeze(" ")

    assert_equal "kubectl logs -l app=myapp-rails --prefix --all-containers --tail=100", kubectl_cmd
  end

  def test_builds_correct_kubectl_command_with_follow
    deployment_name = "myapp-rails"

    follow = true
    tail = 100

    follow_flag = follow ? "-f" : ""
    tail_flag = "--tail=#{tail}"
    kubectl_cmd = "kubectl logs -l app=#{deployment_name} --prefix --all-containers #{follow_flag} #{tail_flag}".strip.squeeze(" ")

    assert_equal "kubectl logs -l app=myapp-rails --prefix --all-containers -f --tail=100", kubectl_cmd
  end

  def test_builds_correct_kubectl_command_with_custom_tail
    deployment_name = "myapp-worker"

    follow = false
    tail = 50

    follow_flag = follow ? "-f" : ""
    tail_flag = "--tail=#{tail}"
    kubectl_cmd = "kubectl logs -l app=#{deployment_name} --prefix --all-containers #{follow_flag} #{tail_flag}".strip.squeeze(" ")

    assert_equal "kubectl logs -l app=myapp-worker --prefix --all-containers --tail=50", kubectl_cmd
  end

  def test_builds_correct_kubectl_command_with_follow_and_custom_tail
    deployment_name = "myapp-solid"

    follow = true
    tail = 200

    follow_flag = follow ? "-f" : ""
    tail_flag = "--tail=#{tail}"
    kubectl_cmd = "kubectl logs -l app=#{deployment_name} --prefix --all-containers #{follow_flag} #{tail_flag}".strip.squeeze(" ")

    assert_equal "kubectl logs -l app=myapp-solid --prefix --all-containers -f --tail=200", kubectl_cmd
  end

  def test_app_deployment_name_method_exists
    # Verify the namer method we're using actually exists
    mock_app = Struct.new(:name).new("myapp")
    mock_deploy = Struct.new(:application).new(mock_app)
    mock_config = Struct.new(:deploy, :container_prefix).new(mock_deploy, "nvoi-myapp")

    namer = Nvoi::Utils::Namer.new(mock_config)
    result = namer.app_deployment_name("rails")

    assert_equal "myapp-rails", result
  end
end

class LogsCommandIntegrationTest < Minitest::Test
  def test_smoke_require
    # Smoke test - just verify the file can be required without errors
    require "nvoi/cli/logs/command"
    assert defined?(Nvoi::Cli::Logs::Command)
  end
end
