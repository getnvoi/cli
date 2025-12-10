# frozen_string_literal: true

require "thor"

module Nvoi
  # Shared options for branch deployments
  module BranchDeploymentOptions
    def self.included(base)
      base.class_option :branch, aliases: "-b", desc: "Branch name for isolated deployments (prefixes app name and subdomains)"
    end

    private

      def build_override
        branch = options[:branch]
        return nil if branch.nil? || branch.empty?

        Config::Override.new(branch:)
      end
  end

  # DbCLI handles database branch operations
  class DbCLI < Thor
    include BranchDeploymentOptions

    class_option :config, aliases: "-c", default: Constants::DEFAULT_CONFIG_FILE,
                          desc: "Path to deployment configuration file"
    class_option :dir, aliases: "-d", default: ".",
                       desc: "Working directory"

    def self.exit_on_failure?
      true
    end

    desc "branch SUBCOMMAND", "Database branch operations"
    subcommand "branch", Class.new(Thor) {
      include BranchDeploymentOptions

      class_option :config, aliases: "-c", default: Constants::DEFAULT_CONFIG_FILE,
                            desc: "Path to deployment configuration file"
      class_option :dir, aliases: "-d", default: ".",
                         desc: "Working directory"

      def self.exit_on_failure?
        true
      end

      desc "create [NAME]", "Create a new database branch (snapshot)"
      long_desc <<~DESC
        Creates a snapshot of the current database state. The snapshot is stored
        on the server and can be restored later using 'nvoi db branch restore'.

        If NAME is not provided, a timestamp-based name will be generated.
      DESC
      def create(name = nil)
        log = Nvoi.logger
        log.info "Database Branch Create"

        config_path = resolve_config_path
        override = build_override
        svc = Service::DbService.new(config_path, log, override:)
        svc.branch_create(name)
      rescue StandardError => e
        log.error "Branch create failed: %s", e.message
        raise
      end

      desc "list", "List all database branches"
      long_desc "Lists all available database snapshots that can be restored."
      def list
        log = Nvoi.logger
        config_path = resolve_config_path
        override = build_override
        svc = Service::DbService.new(config_path, log, override:)
        branches = svc.branch_list

        if branches.empty?
          log.info "No branches found"
        else
          log.info "Database branches:"
          log.info ""
          log.info "%-20s %-20s %-12s %-10s", "ID", "Created", "Size", "Adapter"
          log.info "-" * 70

          branches.each do |b|
            size_str = format_size(b.size)
            created = b.created_at[0, 19].gsub("T", " ") rescue b.created_at
            log.info "%-20s %-20s %-12s %-10s", b.id, created, size_str, b.adapter
          end
        end
      rescue StandardError => e
        log.error "Branch list failed: %s", e.message
        raise
      end

      desc "restore ID [NEW_DB_NAME]", "Restore a database branch to a new database"
      long_desc <<~DESC
        Restores a previously created snapshot to a NEW database. The original
        database remains unchanged.

        If NEW_DB_NAME is not provided, it will be generated as: {original_db}_{branch_id}

        After restoring, you'll need to update your credentials to point to the
        new database using 'nvoi credentials set'.
      DESC
      def restore(branch_id, new_db_name = nil)
        log = Nvoi.logger
        log.info "Database Branch Restore"

        config_path = resolve_config_path
        override = build_override
        svc = Service::DbService.new(config_path, log, override:)
        svc.branch_restore(branch_id, new_db_name)
      rescue StandardError => e
        log.error "Branch restore failed: %s", e.message
        raise
      end

      desc "download ID [--path FILE]", "Download a database branch dump"
      long_desc <<~DESC
        Downloads a database snapshot to your local machine. Useful for local
        development or creating off-site backups.
      DESC
      option :path, aliases: "-p", desc: "Output file path (default: {branch_id}.sql)"
      def download(branch_id)
        log = Nvoi.logger
        log.info "Database Branch Download"

        config_path = resolve_config_path
        override = build_override
        svc = Service::DbService.new(config_path, log, override:)
        svc.branch_download(branch_id, options[:path])
      rescue StandardError => e
        log.error "Branch download failed: %s", e.message
        raise
      end

      private

        def resolve_config_path
          config_path = options[:config]
          working_dir = options[:dir]

          if config_path == Constants::DEFAULT_CONFIG_FILE && working_dir && working_dir != "."
            File.join(working_dir, Constants::DEFAULT_CONFIG_FILE)
          else
            config_path
          end
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
    }
  end

  # CredentialsCLI handles encrypted credential management
  class CredentialsCLI < Thor
    class_option :credentials, desc: "Path to encrypted credentials file (default: deploy.enc)"
    class_option :master_key, desc: "Path to master key file (default: deploy.key or $NVOI_MASTER_KEY)"
    class_option :dir, aliases: "-d", default: ".", desc: "Working directory"

    def self.exit_on_failure?
      true
    end

    desc "edit", "Edit encrypted credentials"
    long_desc <<~DESC
      Decrypt credentials, open in $EDITOR, validate, and re-encrypt.

      On first run, generates a new master key and creates deploy.key (git-ignored).
      The master key can also be provided via $NVOI_MASTER_KEY environment variable.
    DESC
    def edit
      log = Nvoi.logger
      log.info "Credentials Editor"

      working_dir = resolve_working_dir

      enc_path = options[:credentials]
      enc_path = File.join(working_dir, Credentials::DEFAULT_ENCRYPTED_FILE) if enc_path.nil? || enc_path.empty?

      if File.exist?(enc_path)
        # Existing file: load manager
        manager = Credentials::Manager.new(working_dir, options[:credentials], options[:master_key])
      else
        # First time: initialize
        log.info "Creating new encrypted credentials file"
        manager = Credentials::Manager.for_init(working_dir)
      end

      editor = Credentials::Editor.new(manager)
      editor.edit

      # Update .gitignore on first run
      if manager.key_path
        begin
          manager.update_gitignore
          log.info "Added %s to .gitignore", Credentials::DEFAULT_KEY_FILE
        rescue StandardError => e
          log.warning "Failed to update .gitignore: %s", e.message
        end

        log.success "Master key saved to: %s", manager.key_path
        log.warning "Keep this key safe! You cannot decrypt credentials without it."
      end
    end

    desc "show", "Display decrypted credentials"
    long_desc "Decrypt and print credentials to stdout. Useful for debugging or piping to other tools."
    def show
      working_dir = resolve_working_dir
      manager = Credentials::Manager.new(working_dir, options[:credentials], options[:master_key])
      editor = Credentials::Editor.new(manager)
      editor.show
    end

    desc "set PATH VALUE", "Set a value at a dot-notation path"
    long_desc <<~DESC
      Update a specific configuration value without manually editing the file.
      The path uses dot notation to navigate the YAML structure.

      Examples:
        nvoi credentials set database.url postgres://user:pass@host/db
        nvoi credentials set database.secrets.POSTGRES_DB myapp_production
        nvoi credentials set env.RAILS_ENV production
    DESC
    def set(path, value)
      log = Nvoi.logger
      working_dir = resolve_working_dir
      manager = Credentials::Manager.new(working_dir, options[:credentials], options[:master_key])

      # Read current content
      content = manager.read
      data = YAML.safe_load(content, permitted_classes: [Symbol])

      # Navigate path and set value
      keys = path.split(".")
      current = data

      # Handle 'application.' prefix - it's implied
      keys.shift if keys.first == "application"

      # Navigate to parent
      keys[0..-2].each do |key|
        current["application"] ||= {}
        current = current["application"]
        current[key] ||= {}
        current = current[key]
      end

      # Set the value
      if keys.length == 1
        data["application"] ||= {}
        data["application"][keys.last] = value
      else
        current[keys.last] = value
      end

      # Write back
      new_content = YAML.dump(data)
      manager.write(new_content)

      log.success "Updated: %s = %s", path, value
    rescue StandardError => e
      log = Nvoi.logger
      log.error "Set failed: %s", e.message
      raise
    end

    private

      def resolve_working_dir
        wd = options[:dir]
        if wd.nil? || wd.empty? || wd == "."
          Dir.pwd
        else
          File.expand_path(wd)
        end
      end
  end

  # Main CLI for nvoi commands
  class CLI < Thor
    include BranchDeploymentOptions

    class_option :config, aliases: "-c", default: Constants::DEFAULT_CONFIG_FILE,
                          desc: "Path to deployment configuration file"
    class_option :dir, aliases: "-d", default: ".",
                       desc: "Working directory containing the application code"

    def self.exit_on_failure?
      true
    end

    desc "version", "Print version"
    def version
      puts "nvoi #{VERSION}"
    end

    desc "deploy", "Deploy application"
    option :dockerfile_path, desc: "Path to Dockerfile (optional, defaults to ./Dockerfile)"
    option :config_dir, desc: "Directory containing SSH keys (optional, defaults to ~/.ssh)"
    def deploy
      log = Nvoi.logger
      log.info "Deploy CLI %s", VERSION

      config_path = resolve_config_path
      working_dir = options[:dir]
      dockerfile_path = options[:dockerfile_path] || File.join(working_dir, "Dockerfile")

      # Build override if branch deployment flags provided
      override = build_override

      begin
        svc = Service::DeployService.new(config_path, working_dir, log, override:)
        svc.config_dir = options[:config_dir] if options[:config_dir]
        svc.dockerfile_path = dockerfile_path
        svc.run
      rescue StandardError => e
        log.error "Deployment failed: %s", e.message
        raise
      end
    end

    desc "delete", "Delete server, firewall, and network"
    option :config_dir, desc: "Directory containing SSH keys (optional, defaults to ~/.ssh)"
    def delete
      log = Nvoi.logger
      log.info "Delete CLI %s", VERSION

      config_path = resolve_config_path

      # Build override if branch deployment flags provided
      override = build_override

      begin
        svc = Service::DeleteService.new(config_path, log, override:)
        svc.config_dir = options[:config_dir] if options[:config_dir]
        svc.run
      rescue StandardError => e
        log.error "Delete failed: %s", e.message
        raise
      end
    end

    desc "exec [COMMAND...]", "Execute command on remote server or open interactive shell"
    long_desc <<~DESC
      Execute arbitrary bash commands on remote servers using existing configuration,
      or open an interactive SSH shell with --interactive flag.
    DESC
    option :server, default: "main", desc: "Server to execute on (main, worker-1, worker-2, etc.)"
    option :all, type: :boolean, default: false, desc: "Execute on all servers"
    option :interactive, aliases: "-i", type: :boolean, default: false,
                         desc: "Open interactive SSH shell instead of executing command"
    def exec(*args)
      log = Nvoi.logger
      log.info "Exec CLI %s", VERSION

      config_path = resolve_config_path

      # Build override if branch deployment flags provided
      override = build_override

      begin
        svc = Service::ExecService.new(config_path, log, override:)

        if options[:interactive]
          log.warning "Ignoring command arguments in interactive mode" unless args.empty?
          log.warning "Ignoring --all flag in interactive mode" if options[:all]
          svc.open_shell(options[:server])
        else
          raise ArgumentError, "command required (use --interactive/-i for shell)" if args.empty?

          command = args.join(" ")

          if options[:all]
            svc.run_all(command)
          else
            svc.run(command, options[:server])
          end
        end
      rescue StandardError => e
        log.error "Exec failed: %s", e.message
        raise
      end
    end

    desc "credentials SUBCOMMAND", "Manage encrypted deployment credentials"
    subcommand "credentials", CredentialsCLI

    desc "db SUBCOMMAND", "Database operations"
    subcommand "db", DbCLI

    private

      def resolve_config_path
        config_path = options[:config]
        working_dir = options[:dir]

        if config_path == Constants::DEFAULT_CONFIG_FILE && working_dir && working_dir != "."
          File.join(working_dir, Constants::DEFAULT_CONFIG_FILE)
        else
          config_path
        end
      end
  end
end
