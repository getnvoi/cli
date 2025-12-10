# frozen_string_literal: true

module Nvoi
  module Service
    # DbService handles database branch operations (backup/restore)
    class DbService
      include ProviderHelper

      BRANCHES_DIR = "/mnt/db-branches"

      def initialize(config_path, log, override: nil)
        @log = log

        # Load configuration
        @config = Config.load(config_path)

        # Apply override for branch deployments
        override&.apply(@config)

        # Initialize provider
        @provider = init_provider(@config)

        # Get database config
        @db_config = @config.deploy.application.database
        raise ServiceError, "No database configured" unless @db_config

        # Get database provider
        adapter = @db_config.adapter&.downcase
        raise ServiceError, "No database adapter configured" unless adapter

        @db_provider = Database.provider_for(adapter)

        # Get credentials
        @creds = Config::DatabaseHelper.get_credentials(@db_config, @config.namer)
      end

      # Create a new branch (snapshot)
      def branch_create(name = nil)
        name ||= generate_branch_id

        @log.info "Creating database branch: %s", name
        @log.separator

        with_ssh do |ssh|
          # Get dump options
          opts = build_dump_options

          # Run dump
          @log.step "Dumping database"
          dump_data = @db_provider.dump(ssh, opts)
          @log.ok "Dump complete (%d bytes)", dump_data.bytesize

          # Save to branches directory
          @log.step "Saving branch"
          app_name = @config.deploy.application.name
          branches_path = "#{BRANCHES_DIR}/#{app_name}"

          # Ensure directory exists
          ssh.execute("mkdir -p #{branches_path}")

          # Write dump file
          dump_file = "#{branches_path}/#{name}.#{@db_provider.extension}"
          write_file_via_ssh(ssh, dump_file, dump_data)

          # Update metadata
          update_branch_metadata(ssh, branches_path, name, dump_data.bytesize)

          @log.ok "Branch saved: %s", dump_file
        end

        @log.separator
        @log.success "Branch created: %s", name

        name
      end

      # List all branches
      def branch_list
        branches = []

        with_ssh do |ssh|
          app_name = @config.deploy.application.name
          branches_path = "#{BRANCHES_DIR}/#{app_name}"
          metadata_file = "#{branches_path}/branches.json"

          # Check if metadata exists
          result = ssh.execute("test -f #{metadata_file} && cat #{metadata_file} || echo '{}'", raise_on_error: false)

          begin
            metadata = Database::BranchMetadata.from_json(result)
            branches = metadata.branches
          rescue JSON::ParserError
            branches = []
          end
        end

        branches
      end

      # Restore a branch to a new database
      def branch_restore(branch_id, new_db_name = nil)
        new_db_name ||= "#{@creds.database}_#{branch_id.gsub("-", "_")}"

        @log.info "Restoring branch %s to database %s", branch_id, new_db_name
        @log.separator

        with_ssh do |ssh|
          app_name = @config.deploy.application.name
          branches_path = "#{BRANCHES_DIR}/#{app_name}"
          dump_file = "#{branches_path}/#{branch_id}.#{@db_provider.extension}"

          # Check if branch exists
          unless ssh.execute("test -f #{dump_file} && echo yes || echo no", raise_on_error: false).strip == "yes"
            raise ServiceError, "Branch not found: #{branch_id}"
          end

          # Read dump data
          @log.step "Reading branch data"
          dump_data = ssh.execute("cat #{dump_file}")

          # Build restore options
          opts = build_restore_options(new_db_name)

          # Run restore
          @log.step "Restoring to new database"
          result = @db_provider.restore(ssh, dump_data, opts)
          @log.ok "Restore complete"

          # For SQLite, result is the new db path
          if @db_provider.is_a?(Database::Sqlite)
            @log.info "New database path: %s", result
          end
        end

        @log.separator
        @log.success "Branch restored: %s -> %s", branch_id, new_db_name

        # Output helper command
        output_credentials_helper(new_db_name)

        new_db_name
      end

      # Download a branch dump to local machine
      def branch_download(branch_id, output_path = nil)
        output_path ||= "#{branch_id}.#{@db_provider.extension}"

        @log.info "Downloading branch: %s", branch_id

        dump_data = nil

        with_ssh do |ssh|
          app_name = @config.deploy.application.name
          branches_path = "#{BRANCHES_DIR}/#{app_name}"
          dump_file = "#{branches_path}/#{branch_id}.#{@db_provider.extension}"

          # Check if branch exists
          unless ssh.execute("test -f #{dump_file} && echo yes || echo no", raise_on_error: false).strip == "yes"
            raise ServiceError, "Branch not found: #{branch_id}"
          end

          # Read dump data
          dump_data = ssh.execute("cat #{dump_file}")
        end

        # Write to local file
        File.write(output_path, dump_data)

        @log.success "Downloaded to: %s (%d bytes)", output_path, dump_data.bytesize

        output_path
      end

      private

        def with_ssh
          # Get server IP
          server_name = @db_config.servers.first
          server_ip = get_server_ip(server_name)
          raise ServiceError, "Could not resolve server IP for: #{server_name}" unless server_ip

          # Create SSH executor
          ssh = Remote::SSHExecutor.new(
            host: server_ip,
            key: @config.deploy.application.ssh_keys.private_key,
            log: @log
          )

          yield ssh
        end

        def get_server_ip(server_name)
          # Try to get from provider
          resolved_name = @config.namer.server_name(server_name, 1)
          @provider.server_ip(resolved_name)
        end

        def build_dump_options
          if @db_provider.is_a?(Database::Sqlite)
            Database::DumpOptions.new(
              host_path: @creds.host_path,
              database: @creds.database
            )
          else
            Database::DumpOptions.new(
              pod_name: @config.namer.database_pod_name,
              database: @creds.database,
              user: @creds.user,
              password: @creds.password
            )
          end
        end

        def build_restore_options(new_db_name)
          if @db_provider.is_a?(Database::Sqlite)
            Database::RestoreOptions.new(
              host_path: @creds.host_path,
              database: Config::DatabaseHelper.sanitize_db_name(new_db_name)
            )
          else
            Database::RestoreOptions.new(
              pod_name: @config.namer.database_pod_name,
              database: Config::DatabaseHelper.sanitize_db_name(new_db_name),
              user: @creds.user,
              password: @creds.password
            )
          end
        end

        def generate_branch_id
          Time.now.strftime("%Y%m%d-%H%M%S")
        end

        def write_file_via_ssh(ssh, path, content)
          # Use heredoc to write content safely
          cmd = "cat > #{path} << 'NVOI_DUMP_EOF'\n#{content}\nNVOI_DUMP_EOF"
          ssh.execute(cmd)
        end

        def update_branch_metadata(ssh, branches_path, branch_id, size)
          metadata_file = "#{branches_path}/branches.json"

          # Read existing metadata
          result = ssh.execute("test -f #{metadata_file} && cat #{metadata_file} || echo '{}'", raise_on_error: false)

          metadata = begin
            Database::BranchMetadata.from_json(result)
          rescue JSON::ParserError
            Database::BranchMetadata.new
          end

          # Add new branch
          metadata.branches << Database::Branch.new(
            id: branch_id,
            created_at: Time.now.iso8601,
            size:,
            adapter: @db_config.adapter,
            database: @creds.database
          )

          # Write updated metadata
          ssh.execute("cat > #{metadata_file} << 'NVOI_META_EOF'\n#{metadata.to_json}\nNVOI_META_EOF")
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
            # For SQLite, update the URL
            new_url = "sqlite://#{File.dirname(@creds.path || "data")}/#{new_db_name}.sqlite3"
            @log.info "  nvoi credentials set database.url %s", new_url
          end
        end
    end
  end
end
