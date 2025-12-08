# frozen_string_literal: true

module Nvoi
  module Service
    # ExecService handles remote command execution on servers
    class ExecService
      include ProviderHelper

      def initialize(config_path, log)
        @log = log

        # Load configuration
        @config = Config.load(config_path)

        # Initialize provider
        @provider = init_provider(@config)
      end

      # Run executes a command on a specific server
      def run(command, server_name)
        # Resolve server name (main, worker-1, etc. -> actual server name)
        actual_server_name = resolve_server_name(server_name)

        # Find server using provider
        server = find_server(actual_server_name)

        @log.info "Connecting to %s (%s)", actual_server_name, server.public_ipv4

        # Create SSH executor
        ssh = Remote::SSHExecutor.new(server.public_ipv4, @config.ssh_key_path)

        # Execute command with streaming output
        @log.info "Executing: %s", command
        output = ssh.execute(command, stream: true)

        # Output is already streamed, but if there's buffered output, show it
        puts output if !output.empty? && !output.include?("\n")

        @log.success "Command completed successfully"
      end

      # RunAll executes a command on all servers (main + workers)
      def run_all(command)
        # Get all server names
        server_names = get_all_server_names

        raise ServiceError, "no servers found in configuration" if server_names.empty?

        @log.info "Executing on %d server(s): %s", server_names.size, server_names.join(", ")
        @log.separator

        # Execute in parallel with threads
        results = {}
        mutex = Mutex.new
        threads = server_names.map do |name|
          Thread.new do
            actual_name = resolve_server_name(name)
            begin
              server = find_server(actual_name)
              ssh = Remote::SSHExecutor.new(server.public_ipv4, @config.ssh_key_path)

              @log.info "[%s] Executing...", name
              output = ssh.execute(command)

              # Print output with server prefix
              output.strip.split("\n").each do |line|
                puts "[#{name}] #{line}"
              end

              mutex.synchronize { results[name] = nil }
            rescue StandardError => e
              @log.error "[%s] Failed: %s", name, e.message
              mutex.synchronize { results[name] = e }
            end
          end
        end

        threads.each(&:join)

        @log.separator

        failures = results.select { |_, err| err }.keys
        if failures.any?
          @log.warning "Command failed on %d server(s): %s", failures.size, failures.join(", ")
          raise ServiceError, "command failed on some servers"
        end

        @log.success "Command completed successfully on all servers"
      end

      # OpenShell opens an interactive SSH shell on a specific server
      def open_shell(server_name)
        actual_server_name = resolve_server_name(server_name)
        server = find_server(actual_server_name)

        @log.info "Opening SSH shell to %s (%s)", actual_server_name, server.public_ipv4

        ssh = Remote::SSHExecutor.new(server.public_ipv4, @config.ssh_key_path)
        ssh.open_shell
      end

      private

        def resolve_server_name(name)
          return @config.server_name if name.nil? || name.empty? || name == "main"

          # Check if name matches "{group}-{n}" pattern
          parts = name.split("-")
          if parts.length >= 2
            num_str = parts.last
            if num_str.match?(/^\d+$/)
              group_name = parts[0...-1].join("-")
              return @config.namer.server_name(group_name, num_str.to_i)
            end
          end

          # Assume it's a group name, return first server
          @config.namer.server_name(name, 1)
        end

        def get_all_server_names
          names = []

          @config.deploy.application.servers.each do |group_name, group_config|
            next unless group_config

            count = group_config.count.positive? ? group_config.count : 1
            (1..count).each do |i|
              names << @config.namer.server_name(group_name, i)
            end
          end

          names
        end

        def find_server(server_name)
          server = @provider.find_server(server_name)
          raise ServiceError, "server not found: #{server_name}" unless server

          server
        end
    end
  end
end
