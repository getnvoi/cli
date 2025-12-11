# frozen_string_literal: true

require "thor"

module Nvoi
  # Main CLI for nvoi commands - Thor routing only
  class Cli < Thor
    class_option :config, aliases: "-c", default: "deploy.enc",
                          desc: "Path to deployment configuration file"
    class_option :dir, aliases: "-d", default: ".",
                       desc: "Working directory containing the application code"
    class_option :branch, aliases: "-b",
                          desc: "Branch name for isolated deployments (prefixes app name and subdomains)"

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
      require_relative "cli/deploy/command"
      Cli::Deploy::Command.new(options).run
    end

    desc "delete", "Delete server, firewall, and network"
    option :config_dir, desc: "Directory containing SSH keys (optional, defaults to ~/.ssh)"
    def delete
      require_relative "cli/delete/command"
      Cli::Delete::Command.new(options).run
    end

    desc "exec [COMMAND...]", "Execute command on remote server or open interactive shell"
    option :server, default: "main", desc: "Server to execute on (main, worker-1, worker-2, etc.)"
    option :all, type: :boolean, default: false, desc: "Execute on all servers"
    option :interactive, aliases: "-i", type: :boolean, default: false,
                         desc: "Open interactive SSH shell instead of executing command"
    def exec(*args)
      require_relative "cli/exec/command"
      Cli::Exec::Command.new(options).run(args)
    end

    desc "credentials SUBCOMMAND", "Manage encrypted deployment credentials"
    subcommand "credentials", Class.new(Thor) {
      def self.exit_on_failure?
        true
      end

      class_option :credentials, desc: "Path to encrypted credentials file (default: deploy.enc)"
      class_option :master_key, desc: "Path to master key file (default: deploy.key or $NVOI_MASTER_KEY)"
      class_option :dir, aliases: "-d", default: ".", desc: "Working directory"

      desc "edit", "Edit encrypted credentials"
      def edit
        require_relative "cli/credentials/edit/command"
        Nvoi::Cli::Credentials::Edit::Command.new(options).run
      end

      desc "show", "Show decrypted credentials"
      def show
        require_relative "cli/credentials/show/command"
        Nvoi::Cli::Credentials::Show::Command.new(options).run
      end

      desc "set PATH VALUE", "Set a value at a dot-notation path"
      def set(path, value)
        require_relative "cli/credentials/edit/command"
        Nvoi::Cli::Credentials::Edit::Command.new(options).set(path, value)
      end
    }

    desc "db SUBCOMMAND", "Database operations"
    subcommand "db", Class.new(Thor) {
      def self.exit_on_failure?
        true
      end

      class_option :config, aliases: "-c", default: "deploy.enc",
                            desc: "Path to deployment configuration file"
      class_option :dir, aliases: "-d", default: ".",
                         desc: "Working directory"
      class_option :branch, aliases: "-b",
                            desc: "Branch name for isolated deployments"

      desc "branch SUBCOMMAND", "Database branch operations"
      subcommand "branch", Class.new(Thor) {
        def self.exit_on_failure?
          true
        end

        class_option :config, aliases: "-c", default: "deploy.enc",
                              desc: "Path to deployment configuration file"
        class_option :dir, aliases: "-d", default: ".",
                           desc: "Working directory"
        class_option :branch, aliases: "-b",
                              desc: "Branch name for isolated deployments"

        desc "create [NAME]", "Create a new database branch (snapshot)"
        def create(name = nil)
          require_relative "cli/db/command"
          Nvoi::Cli::Db::Command.new(options).branch_create(name)
        end

        desc "list", "List all database branches"
        def list
          require_relative "cli/db/command"
          Nvoi::Cli::Db::Command.new(options).branch_list
        end

        desc "restore ID [NEW_DB_NAME]", "Restore a database branch to a new database"
        def restore(branch_id, new_db_name = nil)
          require_relative "cli/db/command"
          Nvoi::Cli::Db::Command.new(options).branch_restore(branch_id, new_db_name)
        end

        desc "download ID", "Download a database branch dump"
        option :path, aliases: "-p", desc: "Output file path (default: {branch_id}.sql)"
        def download(branch_id)
          require_relative "cli/db/command"
          Nvoi::Cli::Db::Command.new(options).branch_download(branch_id)
        end
      }
    }
  end
end
