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

    desc "onboard", "Interactive setup wizard"
    def onboard
      Cli::Onboard::Command.new.run
    end

    desc "deploy", "Deploy application"
    option :dockerfile_path, desc: "Path to Dockerfile (optional, defaults to ./Dockerfile)"
    option :config_dir, desc: "Directory containing SSH keys (optional, defaults to ~/.ssh)"
    def deploy
      Cli::Deploy::Command.new(options).run
    end

    desc "delete", "Delete server, firewall, and network"
    option :config_dir, desc: "Directory containing SSH keys (optional, defaults to ~/.ssh)"
    def delete
      Cli::Delete::Command.new(options).run
    end

    desc "unlock", "Remove deployment lock (use when deploy hangs)"
    def unlock
      Cli::Unlock::Command.new(options).run
    end

    desc "logs APP_NAME", "Stream logs from an app"
    option :follow, aliases: "-f", type: :boolean, default: false, desc: "Follow log output"
    option :tail, aliases: "-n", type: :numeric, default: 100, desc: "Number of lines to show"
    def logs(app_name)
      Cli::Logs::Command.new(options).run(app_name)
    end

    desc "exec [COMMAND...]", "Execute command on remote server or open interactive shell"
    option :server, default: "main", desc: "Server to execute on (main, worker-1, worker-2, etc.)"
    option :all, type: :boolean, default: false, desc: "Execute on all servers"
    option :interactive, aliases: "-i", type: :boolean, default: false,
                         desc: "Open interactive SSH shell instead of executing command"
    def exec(*args)
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
        Nvoi::Cli::Credentials::Edit::Command.new(options).run
      end

      desc "show", "Show decrypted credentials"
      def show
        Nvoi::Cli::Credentials::Show::Command.new(options).run
      end

      desc "set PATH VALUE", "Set a value at a dot-notation path"
      def set(path, value)
        Nvoi::Cli::Credentials::Edit::Command.new(options).set(path, value)
      end
    }

    desc "config SUBCOMMAND", "Manage deployment configuration"
    subcommand "config", Class.new(Thor) {
      def self.exit_on_failure?
        true
      end

      class_option :credentials, desc: "Path to encrypted config file"
      class_option :master_key, desc: "Path to master key file"
      class_option :dir, aliases: "-d", default: ".", desc: "Working directory"

      desc "init", "Initialize new config"
      option :name, required: true, desc: "Application name"
      option :environment, default: "production", desc: "Environment"
      def init
        Nvoi::Cli::Config::Command.new(options).init(options[:name], options[:environment])
      end

      desc "provider SUBCOMMAND", "Manage compute provider"
      subcommand "provider", Class.new(Thor) {
        def self.exit_on_failure? = true
        class_option :credentials, desc: "Path to encrypted config file"
        class_option :master_key, desc: "Path to master key file"
        class_option :dir, aliases: "-d", default: ".", desc: "Working directory"

        desc "set PROVIDER", "Set compute provider (hetzner, aws, scaleway)"
        option :api_token, desc: "API token (hetzner)"
        option :server_type, desc: "Server type (cx22, etc)"
        option :server_location, desc: "Location (fsn1, etc)"
        option :architecture, desc: "CPU architecture (x86, arm64)"
        option :access_key_id, desc: "AWS access key ID"
        option :secret_access_key, desc: "AWS secret access key"
        option :region, desc: "AWS region"
        option :instance_type, desc: "AWS instance type"
        option :secret_key, desc: "Scaleway secret key"
        option :project_id, desc: "Scaleway project ID"
        option :zone, desc: "Scaleway zone"
        def set(provider)
          Nvoi::Cli::Config::Command.new(options).provider_set(provider, **options.slice(
            :api_token, :server_type, :server_location, :architecture,
            :access_key_id, :secret_access_key, :region, :instance_type,
            :secret_key, :project_id, :zone
          ).transform_keys(&:to_sym).compact)
        end

        desc "rm", "Remove compute provider"
        def rm
          Nvoi::Cli::Config::Command.new(options).provider_rm
        end
      }

      desc "domain SUBCOMMAND", "Manage domain provider"
      subcommand "domain", Class.new(Thor) {
        def self.exit_on_failure? = true
        class_option :credentials, desc: "Path to encrypted config file"
        class_option :master_key, desc: "Path to master key file"
        class_option :dir, aliases: "-d", default: ".", desc: "Working directory"

        desc "set PROVIDER", "Set domain provider (cloudflare)"
        option :api_token, required: true, desc: "API token"
        option :account_id, required: true, desc: "Account ID"
        def set(provider)
          Nvoi::Cli::Config::Command.new(options).domain_set(provider, api_token: options[:api_token], account_id: options[:account_id])
        end

        desc "rm", "Remove domain provider"
        def rm
          Nvoi::Cli::Config::Command.new(options).domain_rm
        end
      }

      desc "server SUBCOMMAND", "Manage servers"
      subcommand "server", Class.new(Thor) {
        def self.exit_on_failure? = true
        class_option :credentials, desc: "Path to encrypted config file"
        class_option :master_key, desc: "Path to master key file"
        class_option :dir, aliases: "-d", default: ".", desc: "Working directory"

        desc "set NAME", "Add or update server"
        option :master, type: :boolean, default: false, desc: "Set as master server"
        option :type, desc: "Server type override"
        option :location, desc: "Location override"
        option :count, type: :numeric, default: 1, desc: "Number of servers"
        def set(name)
          Nvoi::Cli::Config::Command.new(options).server_set(name, master: options[:master], type: options[:type], location: options[:location], count: options[:count])
        end

        desc "rm NAME", "Remove server"
        def rm(name)
          Nvoi::Cli::Config::Command.new(options).server_rm(name)
        end
      }

      desc "volume SUBCOMMAND", "Manage volumes"
      subcommand "volume", Class.new(Thor) {
        def self.exit_on_failure? = true
        class_option :credentials, desc: "Path to encrypted config file"
        class_option :master_key, desc: "Path to master key file"
        class_option :dir, aliases: "-d", default: ".", desc: "Working directory"

        desc "set SERVER NAME", "Add or update volume"
        option :size, type: :numeric, default: 10, desc: "Volume size in GB"
        def set(server, name)
          Nvoi::Cli::Config::Command.new(options).volume_set(server, name, size: options[:size])
        end

        desc "rm SERVER NAME", "Remove volume"
        def rm(server, name)
          Nvoi::Cli::Config::Command.new(options).volume_rm(server, name)
        end
      }

      desc "app SUBCOMMAND", "Manage applications"
      subcommand "app", Class.new(Thor) {
        def self.exit_on_failure? = true
        class_option :credentials, desc: "Path to encrypted config file"
        class_option :master_key, desc: "Path to master key file"
        class_option :dir, aliases: "-d", default: ".", desc: "Working directory"

        desc "set NAME", "Add or update app"
        option :servers, type: :array, required: true, desc: "Server names to run on"
        option :domain, desc: "Domain"
        option :subdomain, desc: "Subdomain"
        option :port, type: :numeric, desc: "Port"
        option :command, desc: "Run command"
        option :pre_run_command, desc: "Pre-run command (migrations, etc)"
        def set(name)
          Nvoi::Cli::Config::Command.new(options).app_set(name, **options.slice(:servers, :domain, :subdomain, :port, :command, :pre_run_command).transform_keys(&:to_sym).compact)
        end

        desc "rm NAME", "Remove app"
        def rm(name)
          Nvoi::Cli::Config::Command.new(options).app_rm(name)
        end
      }

      desc "database SUBCOMMAND", "Manage database"
      subcommand "database", Class.new(Thor) {
        def self.exit_on_failure? = true
        class_option :credentials, desc: "Path to encrypted config file"
        class_option :master_key, desc: "Path to master key file"
        class_option :dir, aliases: "-d", default: ".", desc: "Working directory"

        desc "set", "Set database configuration"
        option :servers, type: :array, required: true, desc: "Server names"
        option :adapter, required: true, desc: "Database adapter (postgres, mysql, sqlite3)"
        option :user, desc: "Database user"
        option :password, desc: "Database password"
        option :database, desc: "Database name"
        option :url, desc: "Database URL (alternative to user/pass/db)"
        option :image, desc: "Custom Docker image"
        def set
          Nvoi::Cli::Config::Command.new(options).database_set(**options.slice(:servers, :adapter, :user, :password, :database, :url, :image).transform_keys(&:to_sym).compact)
        end

        desc "rm", "Remove database"
        def rm
          Nvoi::Cli::Config::Command.new(options).database_rm
        end
      }

      desc "service SUBCOMMAND", "Manage services (redis, etc)"
      subcommand "service", Class.new(Thor) {
        def self.exit_on_failure? = true
        class_option :credentials, desc: "Path to encrypted config file"
        class_option :master_key, desc: "Path to master key file"
        class_option :dir, aliases: "-d", default: ".", desc: "Working directory"

        desc "set NAME", "Add or update service"
        option :servers, type: :array, required: true, desc: "Server names"
        option :image, required: true, desc: "Docker image"
        option :port, type: :numeric, desc: "Port"
        option :command, desc: "Command"
        def set(name)
          Nvoi::Cli::Config::Command.new(options).service_set(name, **options.slice(:servers, :image, :port, :command).transform_keys(&:to_sym).compact)
        end

        desc "rm NAME", "Remove service"
        def rm(name)
          Nvoi::Cli::Config::Command.new(options).service_rm(name)
        end
      }

      desc "secret SUBCOMMAND", "Manage secrets"
      subcommand "secret", Class.new(Thor) {
        def self.exit_on_failure? = true
        class_option :credentials, desc: "Path to encrypted config file"
        class_option :master_key, desc: "Path to master key file"
        class_option :dir, aliases: "-d", default: ".", desc: "Working directory"

        desc "set KEY VALUE", "Set secret"
        def set(key, value)
          Nvoi::Cli::Config::Command.new(options).secret_set(key, value)
        end

        desc "rm KEY", "Remove secret"
        def rm(key)
          Nvoi::Cli::Config::Command.new(options).secret_rm(key)
        end
      }

      desc "env SUBCOMMAND", "Manage environment variables"
      subcommand "env", Class.new(Thor) {
        def self.exit_on_failure? = true
        class_option :credentials, desc: "Path to encrypted config file"
        class_option :master_key, desc: "Path to master key file"
        class_option :dir, aliases: "-d", default: ".", desc: "Working directory"

        desc "set KEY VALUE", "Set environment variable"
        def set(key, value)
          Nvoi::Cli::Config::Command.new(options).env_set(key, value)
        end

        desc "rm KEY", "Remove environment variable"
        def rm(key)
          Nvoi::Cli::Config::Command.new(options).env_rm(key)
        end
      }
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
          Nvoi::Cli::Db::Command.new(options).branch_create(name)
        end

        desc "list", "List all database branches"
        def list
          Nvoi::Cli::Db::Command.new(options).branch_list
        end

        desc "restore ID [NEW_DB_NAME]", "Restore a database branch to a new database"
        def restore(branch_id, new_db_name = nil)
          Nvoi::Cli::Db::Command.new(options).branch_restore(branch_id, new_db_name)
        end

        desc "download ID", "Download a database branch dump"
        option :path, aliases: "-p", desc: "Output file path (default: {branch_id}.sql)"
        def download(branch_id)
          Nvoi::Cli::Db::Command.new(options).branch_download(branch_id)
        end
      }
    }
  end
end
