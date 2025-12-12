# frozen_string_literal: true

require "net/ssh"

module Nvoi
  module External
    # SshTunnel manages SSH port forwarding using net-ssh
    class SshTunnel
      attr_reader :local_port, :remote_port

      def initialize(ip:, user:, key_path:, local_port:, remote_port:)
        @ip = ip
        @user = user
        @key_path = key_path
        @local_port = local_port
        @remote_port = remote_port
        @session = nil
        @thread = nil
        @running = false
      end

      def start
        Nvoi.logger.info "Starting SSH tunnel: localhost:%d -> %s:%d", @local_port, @ip, @remote_port

        @session = Net::SSH.start(
          @ip,
          @user,
          keys: [@key_path],
          non_interactive: true,
          verify_host_key: :never
        )

        @session.forward.local(@local_port, "localhost", @remote_port)
        @running = true

        @thread = Thread.new do
          Thread.current.report_on_exception = false
          @session.loop { @running }
        rescue IOError, Net::SSH::Disconnect, Errno::EBADF
          # Session closed during shutdown, exit gracefully
        end

        # Wait for tunnel to establish
        sleep 0.3
        verify_tunnel!

        Nvoi.logger.success "SSH tunnel established"
      end

      def stop
        return unless @running

        Nvoi.logger.info "Stopping SSH tunnel"
        @running = false

        # Give the event loop a moment to see @running = false
        sleep 0.1

        begin
          @session&.forward&.cancel_local(@local_port)
        rescue StandardError
          # Ignore errors during cleanup
        end

        begin
          @session&.close
        rescue StandardError
          # Ignore errors during cleanup
        end

        # Wait for thread to exit gracefully
        @thread&.join(1)

        @session = nil
        @thread = nil

        Nvoi.logger.success "SSH tunnel closed"
      end

      def alive?
        @running && @thread&.alive? && @session && !@session.closed?
      end

      private

        def verify_tunnel!
          unless alive?
            raise Errors::SshError, "SSH tunnel failed to start"
          end

          # Verify the port is actually listening
          require "socket"
          socket = TCPSocket.new("localhost", @local_port)
          socket.close
        rescue Errno::ECONNREFUSED
          raise Errors::SshError, "SSH tunnel started but port #{@local_port} not accessible"
        end
    end
  end
end
