# frozen_string_literal: true

module Nvoi
  class Cli
    module Exec
      # Command handles remote command execution on servers
      class Command
        def initialize(options)
          @options = options
          @log = Nvoi.logger
        end

        def run(args)
          @log.info "Exec CLI %s", VERSION

          # Load configuration
          config_path = resolve_config_path
          @config = Utils::ConfigLoader.load(config_path)

          # Apply branch override if specified
          apply_branch_override if @options[:branch]

          # Initialize cloud provider
          @provider = External::Cloud.for(@config)

          if @options[:interactive]
            @log.warning "Ignoring command arguments in interactive mode" unless args.empty?
            @log.warning "Ignoring --all flag in interactive mode" if @options[:all]
            open_shell(@options[:server])
          else
            raise ArgumentError, "command required (use --interactive/-i for shell)" if args.empty?

            command = args.join(" ")

            if @options[:all]
              run_all(command)
            else
              run_on_server(command, @options[:server])
            end
          end
        end

        private

          def resolve_config_path
            config_path = @options[:config] || "deploy.enc"
            working_dir = @options[:dir]

            if config_path == "deploy.enc" && working_dir && working_dir != "."
              File.join(working_dir, "deploy.enc")
            else
              config_path
            end
          end

          def apply_branch_override
            branch = @options[:branch]
            return if branch.nil? || branch.empty?

            override = Objects::ConfigOverride.new(branch:)
            override.apply(@config)
          end

          def run_on_server(command, server_name)
            actual_server_name = resolve_server_name(server_name)
            server = find_server(actual_server_name)

            @log.info "Connecting to %s (%s)", actual_server_name, server.public_ipv4

            ssh = External::Ssh.new(server.public_ipv4, @config.ssh_key_path)

            @log.info "Executing: %s", command
            output = ssh.execute(command, stream: true)

            puts output if !output.empty? && !output.include?("\n")

            @log.success "Command completed successfully"
          end

          def run_all(command)
            server_names = get_all_server_names

            raise Errors::ServiceError, "no servers found in configuration" if server_names.empty?

            @log.info "Executing on %d server(s): %s", server_names.size, server_names.join(", ")
            @log.separator

            results = {}
            mutex = Mutex.new
            threads = server_names.map do |name|
              Thread.new do
                actual_name = resolve_server_name(name)
                begin
                  server = find_server(actual_name)
                  ssh = External::Ssh.new(server.public_ipv4, @config.ssh_key_path)

                  @log.info "[%s] Executing...", name
                  output = ssh.execute(command)

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
              raise Errors::ServiceError, "command failed on some servers"
            end

            @log.success "Command completed successfully on all servers"
          end

          def open_shell(server_name)
            actual_server_name = resolve_server_name(server_name)
            server = find_server(actual_server_name)

            @log.info "Opening SSH shell to %s (%s)", actual_server_name, server.public_ipv4

            ssh = External::Ssh.new(server.public_ipv4, @config.ssh_key_path)
            ssh.open_shell
          end

          def resolve_server_name(name)
            return @config.server_name if name.nil? || name.empty? || name == "main"

            parts = name.split("-")
            if parts.length >= 2
              num_str = parts.last
              if num_str.match?(/^\d+$/)
                group_name = parts[0...-1].join("-")
                return @config.namer.server_name(group_name, num_str.to_i)
              end
            end

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
            raise Errors::ServiceError, "server not found: #{server_name}" unless server

            server
          end
      end
    end
  end
end
