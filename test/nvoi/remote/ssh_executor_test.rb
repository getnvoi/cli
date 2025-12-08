# frozen_string_literal: true

require "test_helper"

class Nvoi::Remote::SSHExecutorTest < Minitest::Test
  def setup
    @ssh = Nvoi::Remote::SSHExecutor.new("192.168.1.100", "/path/to/key")
  end

  def test_initializes_with_correct_attributes
    assert_equal "192.168.1.100", @ssh.ip
    assert_equal "/path/to/key", @ssh.ssh_key
    assert_equal "deploy", @ssh.user
  end

  def test_execute_runs_ssh_command
    mock_status = Minitest::Mock.new
    mock_status.expect :success?, true

    Open3.stub(:capture2e, ["command output\n", mock_status]) do
      result = @ssh.execute("echo hello")
      assert_equal "command output", result
    end

    mock_status.verify
  end

  def test_execute_raises_on_failure
    mock_status = Minitest::Mock.new
    mock_status.expect :success?, false
    mock_status.expect :exitstatus, 1

    Open3.stub(:capture2e, ["error message", mock_status]) do
      assert_raises(Nvoi::SSHCommandError) do
        @ssh.execute("failing command")
      end
    end

    mock_status.verify
  end

  def test_execute_quiet_swallows_errors
    mock_status = Minitest::Mock.new
    mock_status.expect :success?, false
    mock_status.expect :exitstatus, 1

    Open3.stub(:capture2e, ["error", mock_status]) do
      # Should not raise
      result = @ssh.execute_quiet("failing command")
      assert_nil result
    end

    mock_status.verify
  end

  def test_builds_correct_ssh_args
    # Access private method via send for testing
    args = @ssh.send(:build_ssh_args)

    assert_includes args, "-o"
    assert_includes args, "LogLevel=ERROR"
    assert_includes args, "-i"
    assert_includes args, "/path/to/key"
    assert_includes args, "StrictHostKeyChecking=no"
  end

  def test_strict_mode_from_env
    original_env = ENV["SSH_STRICT_HOST_KEY_CHECKING"]
    ENV["SSH_STRICT_HOST_KEY_CHECKING"] = "true"

    begin
      ssh = Nvoi::Remote::SSHExecutor.new("192.168.1.100", "/path/to/key")
      args = ssh.send(:build_ssh_args)

      assert_includes args, "StrictHostKeyChecking=accept-new"
    ensure
      if original_env
        ENV["SSH_STRICT_HOST_KEY_CHECKING"] = original_env
      else
        ENV.delete("SSH_STRICT_HOST_KEY_CHECKING")
      end
    end
  end
end

class Nvoi::Remote::SSHExecutorIntegrationTest < Minitest::Test
  # Integration tests that verify SSH command building and execution flow
  # without actually connecting to remote servers

  def test_full_command_construction
    ssh = Nvoi::Remote::SSHExecutor.new("10.0.0.5", "/home/user/.ssh/id_rsa")

    # Mock the Open3 call and capture the actual command
    captured_command = nil

    mock_status = Minitest::Mock.new
    mock_status.expect :success?, true

    Open3.stub(:capture2e, ->(*args) {
      captured_command = args
      ["output", mock_status]
    }) do
      ssh.execute("kubectl get pods")
    end

    # Verify command structure
    assert_equal "ssh", captured_command[0]
    assert_includes captured_command, "-o"
    assert_includes captured_command, "-i"
    assert_includes captured_command, "/home/user/.ssh/id_rsa"
    assert_includes captured_command, "deploy@10.0.0.5"
    assert_includes captured_command, "kubectl get pods"

    mock_status.verify
  end

  def test_strips_output_whitespace
    ssh = Nvoi::Remote::SSHExecutor.new("10.0.0.5", "/home/user/.ssh/id_rsa")

    mock_status = Minitest::Mock.new
    mock_status.expect :success?, true

    Open3.stub(:capture2e, ["  trimmed output  \n\n", mock_status]) do
      result = ssh.execute("echo test")
      assert_equal "trimmed output", result
    end

    mock_status.verify
  end

  def test_includes_exit_code_in_error
    ssh = Nvoi::Remote::SSHExecutor.new("10.0.0.5", "/home/user/.ssh/id_rsa")

    mock_status = Minitest::Mock.new
    mock_status.expect :success?, false
    mock_status.expect :exitstatus, 127

    Open3.stub(:capture2e, ["command not found", mock_status]) do
      error = assert_raises(Nvoi::SSHCommandError) do
        ssh.execute("nonexistent-command")
      end

      assert_includes error.message, "127"
      assert_includes error.message, "command not found"
    end

    mock_status.verify
  end
end
