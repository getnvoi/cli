# frozen_string_literal: true

module Nvoi
  class Cli
    module Db
      # Command handles database branch operations (backup/restore)
      class Command
        BRANCHES_DIR = "/mnt/db-branches"

        def initialize(options)
          @options = options
          @log = Nvoi.logger
        end

        def branch_create(name = nil)
          init_db_context

          name ||= generate_branch_id

          @log.info "Creating database branch: %s", name
          @log.separator

          with_ssh do |ssh|
            opts = build_dump_options

            @log.step "Dumping database"
            dump_data = @db_provider.dump(ssh, opts)
            @log.ok "Dump complete (%d bytes)", dump_data.bytesize

            @log.step "Saving branch"
            app_name = @config.deploy.application.name
            branches_path = "#{BRANCHES_DIR}/#{app_name}"

            ssh.execute("mkdir -p #{branches_path}")

            dump_file = "#{branches_path}/#{name}.#{@db_provider.extension}"
            write_file_via_ssh(ssh, dump_file, dump_data)

            update_branch_metadata(ssh, branches_path, name, dump_data.bytesize)

            @log.ok "Branch saved: %s", dump_file
          end

          @log.separator
          @log.success "Branch created: %s", name

          name
        end

        def branch_list
          init_db_context

          branches = []

          with_ssh do |ssh|
            app_name = @config.deploy.application.name
            branches_path = "#{BRANCHES_DIR}/#{app_name}"
            metadata_file = "#{branches_path}/branches.json"

            result = ssh.execute("test -f #{metadata_file} && cat #{metadata_file} || echo '{}'")

            begin
              metadata = Objects::BranchMetadata.from_json(result)
              branches = metadata.branches
            rescue JSON::ParserError
              branches = []
            end
          end

          if branches.empty?
            @log.info "No branches found"
          else
            @log.info "Database branches:"
            @log.info ""
            @log.info "%-20s %-20s %-12s %-10s", "ID", "Created", "Size", "Adapter"
            @log.info "-" * 70

            branches.each do |b|
              size_str = format_size(b.size)
              created = b.created_at[0, 19].gsub("T", " ") rescue b.created_at
              @log.info "%-20s %-20s %-12s %-10s", b.id, created, size_str, b.adapter
            end
          end

          branches
        end

        def branch_restore(branch_id, new_db_name = nil)
          init_db_context

          new_db_name ||= "#{@creds.database}_#{branch_id.gsub('-', '_')}"

          @log.info "Restoring branch %s to database %s", branch_id, new_db_name
          @log.separator

          with_ssh do |ssh|
            app_name = @config.deploy.application.name
            branches_path = "#{BRANCHES_DIR}/#{app_name}"
            dump_file = "#{branches_path}/#{branch_id}.#{@db_provider.extension}"

            unless ssh.execute("test -f #{dump_file} && echo yes || echo no").strip == "yes"
              raise ServiceError, "Branch not found: #{branch_id}"
            end

            @log.step "Reading branch data"
            dump_data = ssh.execute("cat #{dump_file}")

            opts = build_restore_options(new_db_name)

            @log.step "Restoring to new database"
            result = @db_provider.restore(ssh, dump_data, opts)
            @log.ok "Restore complete"

            if @db_provider.is_a?(External::Database::Sqlite)
              @log.info "New database path: %s", result
            end
          end

          @log.separator
          @log.success "Branch restored: %s -> %s", branch_id, new_db_name

          output_credentials_helper(new_db_name)

          new_db_name
        end

        def branch_download(branch_id)
          init_db_context

          output_path = @options[:path] || "#{branch_id}.#{@db_provider.extension}"

          @log.info "Downloading branch: %s", branch_id

          dump_data = nil

          with_ssh do |ssh|
            app_name = @config.deploy.application.name
            branches_path = "#{BRANCHES_DIR}/#{app_name}"
            dump_file = "#{branches_path}/#{branch_id}.#{@db_provider.extension}"

            unless ssh.execute("test -f #{dump_file} && echo yes || echo no").strip == "yes"
              raise ServiceError, "Branch not found: #{branch_id}"
            end

            dump_data = ssh.execute("cat #{dump_file}")
          end

          File.write(output_path, dump_data)

          @log.success "Downloaded to: %s (%d bytes)", output_path, dump_data.bytesize

          output_path
        end

        private

          def init_db_context
            config_path = resolve_config_path
            @config = Utils::ConfigLoader.load(config_path)

            apply_branch_override if @options[:branch]

            @provider = External::Cloud.for(@config)

            @db_config = @config.deploy.application.database
            raise ServiceError, "No database configured" unless @db_config

            adapter = @db_config.adapter&.downcase
            raise ServiceError, "No database adapter configured" unless adapter

            @db_provider = External::Database.provider_for(adapter)
            @creds = Utils::ConfigLoader.get_database_credentials(@db_config, @config.namer)
          end

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

            override = Objects::ConfigOverride.new(branch: branch)
            override.apply(@config)
          end

          def with_ssh
            server_name = @db_config.servers.first
            resolved_name = @config.namer.server_name(server_name, 1)
            server = @provider.find_server(resolved_name)
            raise ServiceError, "Could not find server: #{server_name}" unless server

            ssh = External::Ssh.new(server.public_ipv4, @config.ssh_key_path)

            yield ssh
          end

          def build_dump_options
            if @db_provider.is_a?(External::Database::Sqlite)
              Objects::DatabaseDumpOptions.new(
                host_path: @creds.host_path,
                database: @creds.database
              )
            else
              Objects::DatabaseDumpOptions.new(
                pod_name: @config.namer.database_pod_name,
                database: @creds.database,
                user: @creds.user,
                password: @creds.password
              )
            end
          end

          def build_restore_options(new_db_name)
            sanitized_name = sanitize_db_name(new_db_name)

            if @db_provider.is_a?(External::Database::Sqlite)
              Objects::DatabaseRestoreOptions.new(
                host_path: @creds.host_path,
                database: sanitized_name
              )
            else
              Objects::DatabaseRestoreOptions.new(
                pod_name: @config.namer.database_pod_name,
                database: sanitized_name,
                user: @creds.user,
                password: @creds.password
              )
            end
          end

          def sanitize_db_name(name)
            name.gsub(/[^a-zA-Z0-9_]/, "_")
          end

          def generate_branch_id
            Time.now.strftime("%Y%m%d-%H%M%S")
          end

          def write_file_via_ssh(ssh, path, content)
            cmd = "cat > #{path} << 'NVOI_DUMP_EOF'\n#{content}\nNVOI_DUMP_EOF"
            ssh.execute(cmd)
          end

          def update_branch_metadata(ssh, branches_path, branch_id, size)
            metadata_file = "#{branches_path}/branches.json"

            result = ssh.execute("test -f #{metadata_file} && cat #{metadata_file} || echo '{}'")

            metadata = begin
              Objects::BranchMetadata.from_json(result)
            rescue JSON::ParserError
              Objects::BranchMetadata.new
            end

            metadata.branches << Objects::DatabaseBranch.new(
              id: branch_id,
              created_at: Time.now.iso8601,
              size: size,
              adapter: @db_config.adapter,
              database: @creds.database
            )

            ssh.execute("cat > #{metadata_file} << 'NVOI_META_EOF'\n#{metadata.to_json}\nNVOI_META_EOF")
          end

          def format_size(bytes)
            return "0 B" unless bytes

            units = %w[B KB MB GB]
            unit_index = 0
            size = bytes.to_f

            while size >= 1024 && unit_index < units.length - 1
              size /= 1024
              unit_index += 1
            end

            format("%.1f %s", size, units[unit_index])
          end

          def output_credentials_helper(new_db_name)
            adapter = @db_config.adapter&.downcase

            @log.info ""
            @log.info "To persist this change, run:"

            case adapter
            when "postgres", "postgresql"
              @log.info "  nvoi credentials set database.secrets.POSTGRES_DB %s", new_db_name
            when "mysql"
              @log.info "  nvoi credentials set database.secrets.MYSQL_DATABASE %s", new_db_name
            when "sqlite", "sqlite3"
              new_url = "sqlite://#{File.dirname(@creds.path || 'data')}/#{new_db_name}.sqlite3"
              @log.info "  nvoi credentials set database.url %s", new_url
            end
          end
      end
    end
  end
end
