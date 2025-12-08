# frozen_string_literal: true

module Nvoi
  module Remote
    # SSHExecutor executes commands on remote servers via SSH
    class SSHExecutor
      attr_reader :ip, :ssh_key, :user

      def initialize(ip, ssh_key)
        @ip = ip
        @ssh_key = ssh_key
        @user = "deploy"
        @strict_mode = ENV["SSH_STRICT_HOST_KEY_CHECKING"] == "true"
      end

      # Execute runs a command on the remote server
      def execute(command, stream: false)
        ssh_args = build_ssh_args
        ssh_args += ["#{@user}@#{@ip}", command]

        if stream
          # Stream output to stdout/stderr for interactive commands
          success = system("ssh", *ssh_args)
          raise SSHCommandError, "SSH command failed" unless success

          ""
        else
          # Capture output
          output, status = Open3.capture2e("ssh", *ssh_args)

          unless status.success?
            raise SSHCommandError, "SSH command failed (exit code: #{status.exitstatus}): #{output}"
          end

          output.strip
        end
      end

      # Execute quietly, ignoring errors (useful for optional cleanup)
      def execute_quiet(command)
        execute(command)
      rescue StandardError
        # Ignore errors
      end

      # Open an interactive SSH shell
      def open_shell
        ssh_args = build_ssh_args
        ssh_args += ["-t", "#{@user}@#{@ip}"]

        exec("ssh", *ssh_args)
      end

      private

      def build_ssh_args
        args = ["-o", "LogLevel=ERROR", "-i", @ssh_key]

        if @strict_mode
          # Use known_hosts verification
          known_hosts_path = File.join(Dir.home, ".ssh", "known_hosts")
          args += ["-o", "StrictHostKeyChecking=accept-new", "-o", "UserKnownHostsFile=#{known_hosts_path}"]
        else
          # Disable host key checking (default for cloud environments)
          args += ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null"]
        end

        args
      end
    end
  end
end
