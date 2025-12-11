# frozen_string_literal: true

require "test_helper"
require "open3"

class ExternalSshTest < Minitest::Test
  def setup
    @ssh = Nvoi::External::Ssh.new("192.168.1.100", "/path/to/key.pem")
  end

  def test_initialize_with_defaults
    assert_equal "192.168.1.100", @ssh.ip
    assert_equal "/path/to/key.pem", @ssh.ssh_key
    assert_equal "deploy", @ssh.user
  end

  def test_initialize_with_custom_user
    ssh = Nvoi::External::Ssh.new("10.0.0.1", "/key.pem", user: "ubuntu")
    assert_equal "ubuntu", ssh.user
  end

  def test_execute_success
    Open3.stub(:capture2e, ["command output\n", Minitest::Mock.new.expect(:success?, true)]) do
      result = @ssh.execute("echo hello")
      assert_equal "command output", result
    end
  end

  def test_execute_failure_raises_ssh_command_error
    status = Minitest::Mock.new
    status.expect(:success?, false)
    status.expect(:exitstatus, 1)

    Open3.stub(:capture2e, ["error output", status]) do
      assert_raises(Nvoi::SSHCommandError) do
        @ssh.execute("bad command")
      end
    end
  end

  def test_execute_ignore_errors_returns_nil_on_failure
    status = Minitest::Mock.new
    status.expect(:success?, false)
    status.expect(:exitstatus, 1)

    Open3.stub(:capture2e, ["error output", status]) do
      result = @ssh.execute_ignore_errors("failing command")
      assert_nil result
    end
  end

  def test_upload_success
    Open3.stub(:capture2e, ["", Minitest::Mock.new.expect(:success?, true)]) do
      @ssh.upload("/local/file.txt", "/remote/file.txt")
    end
  end

  def test_upload_failure_raises_error
    status = Minitest::Mock.new
    status.expect(:success?, false)

    Open3.stub(:capture2e, ["Permission denied", status]) do
      assert_raises(Nvoi::SSHCommandError) do
        @ssh.upload("/local/file.txt", "/remote/file.txt")
      end
    end
  end

  def test_download_success
    Open3.stub(:capture2e, ["", Minitest::Mock.new.expect(:success?, true)]) do
      @ssh.download("/remote/file.txt", "/local/file.txt")
    end
  end

  def test_download_failure_raises_error
    status = Minitest::Mock.new
    status.expect(:success?, false)

    Open3.stub(:capture2e, ["File not found", status]) do
      assert_raises(Nvoi::SSHCommandError) do
        @ssh.download("/remote/file.txt", "/local/file.txt")
      end
    end
  end

  def test_rsync_success
    Open3.stub(:capture2e, ["", Minitest::Mock.new.expect(:success?, true)]) do
      @ssh.rsync("/local/dir/", "/remote/dir/")
    end
  end

  def test_rsync_failure_raises_error
    status = Minitest::Mock.new
    status.expect(:success?, false)

    Open3.stub(:capture2e, ["rsync error", status]) do
      assert_raises(Nvoi::SSHCommandError) do
        @ssh.rsync("/local/dir/", "/remote/dir/")
      end
    end
  end
end
