# frozen_string_literal: true

module Nvoi
  module External
    # Ssh handles command execution on remote servers
    class Ssh
      attr_reader :ip, :ssh_key, :user

      def initialize(ip, ssh_key, user: "deploy")
        @ip = ip
        @ssh_key = ssh_key
        @user = user
        @strict_mode = ENV["SSH_STRICT_HOST_KEY_CHECKING"] == "true"
      end

      def execute(command, stream: false)
        ssh_args = build_ssh_args
        ssh_args += ["#{@user}@#{@ip}", command]

        if stream
          success = system("ssh", *ssh_args)
          raise Errors::SshCommandError, "SSH command failed" unless success

          ""
        else
          output, status = Open3.capture2e("ssh", *ssh_args)

          unless status.success?
            raise Errors::SshCommandError, "SSH command failed (exit code: #{status.exitstatus}): #{output}"
          end

          output.strip
        end
      end

      def execute_ignore_errors(command)
        execute(command)
      rescue StandardError
        nil
      end

      def open_shell
        ssh_args = build_ssh_args
        ssh_args += ["-t", "#{@user}@#{@ip}"]

        exec("ssh", *ssh_args)
      end

      def upload(local_path, remote_path)
        scp_args = build_scp_args
        scp_args += [local_path, "#{@user}@#{@ip}:#{remote_path}"]

        output, status = Open3.capture2e("scp", *scp_args)
        raise Errors::SshCommandError, "SCP upload failed: #{output}" unless status.success?
      end

      def download(remote_path, local_path)
        scp_args = build_scp_args
        scp_args += ["#{@user}@#{@ip}:#{remote_path}", local_path]

        output, status = Open3.capture2e("scp", *scp_args)
        raise Errors::SshCommandError, "SCP download failed: #{output}" unless status.success?
      end

      private

        def build_ssh_args
          args = ["-o", "LogLevel=ERROR", "-i", @ssh_key]

          if @strict_mode
            known_hosts_path = File.join(Dir.home, ".ssh", "known_hosts")
            args += ["-o", "StrictHostKeyChecking=accept-new", "-o", "UserKnownHostsFile=#{known_hosts_path}"]
          else
            args += ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null"]
          end

          args
        end

        def build_scp_args
          args = ["-o", "LogLevel=ERROR", "-i", @ssh_key]

          if @strict_mode
            known_hosts_path = File.join(Dir.home, ".ssh", "known_hosts")
            args += ["-o", "StrictHostKeyChecking=accept-new", "-o", "UserKnownHostsFile=#{known_hosts_path}"]
          else
            args += ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null"]
          end

          args
        end
    end
  end
end
