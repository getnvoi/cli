# frozen_string_literal: true

require "thor"

module Nvoi
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

      begin
        svc = Service::DeployService.new(config_path, working_dir, log)
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

      begin
        svc = Service::DeleteService.new(config_path, log)
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

      begin
        svc = Service::ExecService.new(config_path, log)

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
