# frozen_string_literal: true

require "test_helper"
require "net/ssh"

class ExternalSshTunnelTest < Minitest::Test
  def setup
    @ip = "192.168.1.100"
    @user = "deploy"
    @key_path = "/path/to/key.pem"
    @local_port = 30500
    @remote_port = 30500
  end

  def test_initialize
    tunnel = Nvoi::External::SshTunnel.new(
      ip: @ip,
      user: @user,
      key_path: @key_path,
      local_port: @local_port,
      remote_port: @remote_port
    )

    assert_equal @local_port, tunnel.local_port
    assert_equal @remote_port, tunnel.remote_port
    refute tunnel.alive?
  end

  def test_alive_returns_false_when_not_started
    tunnel = Nvoi::External::SshTunnel.new(
      ip: @ip,
      user: @user,
      key_path: @key_path,
      local_port: @local_port,
      remote_port: @remote_port
    )

    refute tunnel.alive?
  end

  def test_stop_is_safe_when_not_started
    tunnel = Nvoi::External::SshTunnel.new(
      ip: @ip,
      user: @user,
      key_path: @key_path,
      local_port: @local_port,
      remote_port: @remote_port
    )

    # Should not raise
    tunnel.stop
    refute tunnel.alive?
  end

  def test_start_raises_on_ssh_connection_failure
    tunnel = Nvoi::External::SshTunnel.new(
      ip: @ip,
      user: @user,
      key_path: @key_path,
      local_port: @local_port,
      remote_port: @remote_port
    )

    Net::SSH.stub(:start, ->(*) { raise Net::SSH::AuthenticationFailed, "Auth failed" }) do
      assert_raises(Net::SSH::AuthenticationFailed) do
        tunnel.start
      end
    end
  end

  def test_start_raises_on_port_verification_failure
    mock_session = Minitest::Mock.new
    mock_forward = Minitest::Mock.new

    mock_forward.expect(:local, nil, [@local_port, "localhost", @remote_port])
    mock_session.expect(:forward, mock_forward)
    mock_session.expect(:closed?, false)

    tunnel = Nvoi::External::SshTunnel.new(
      ip: @ip,
      user: @user,
      key_path: @key_path,
      local_port: @local_port,
      remote_port: @remote_port
    )

    Net::SSH.stub(:start, mock_session) do
      # TCPSocket.new will fail with connection refused
      assert_raises(Nvoi::Errors::SshError) do
        tunnel.start
      end
    end
  end

  def test_thread_handles_ebadf_on_shutdown_gracefully
    # Simulates the race condition where session.close happens
    # while the event loop thread is still running
    tunnel = Nvoi::External::SshTunnel.new(
      ip: @ip,
      user: @user,
      key_path: @key_path,
      local_port: @local_port,
      remote_port: @remote_port
    )

    # Create a mock session that raises EBADF when loop is called after close
    mock_session = Object.new
    mock_forward = Object.new

    def mock_forward.local(*); end
    def mock_forward.cancel_local(*); end

    def mock_session.forward; @forward ||= Object.new.tap { |f| def f.local(*); end; def f.cancel_local(*); end }; end
    def mock_session.closed?; @closed; end
    def mock_session.close; @closed = true; end

    # Simulate the event loop that raises EBADF on close
    call_count = 0
    mock_session.define_singleton_method(:loop) do |&block|
      while block.call
        call_count += 1
        sleep 0.01
        raise Errno::EBADF, "Bad file descriptor" if @closed
      end
    end

    Net::SSH.stub(:start, mock_session) do
      TCPSocket.stub(:new, ->(*) { Object.new.tap { |s| def s.close; end } }) do
        tunnel.start
        assert tunnel.alive?

        # Stop should not raise despite EBADF in thread
        tunnel.stop
        refute tunnel.alive?
      end
    end
  end
end
