# frozen_string_literal: true

module Nvoi
  module Credentials
    DEFAULT_EDITOR = "vim"
    TEMP_FILE_PATTERN = "nvoi-credentials-"

    # Editor handles the edit workflow
    class Editor
      def initialize(manager)
        @manager = manager
        @editor = ENV["EDITOR"] || DEFAULT_EDITOR
      end

      # Perform the full edit cycle: decrypt -> edit -> validate -> encrypt
      def edit
        is_first_time = !@manager.exists?

        content = if is_first_time
          default_template
        else
          @manager.read
        end

        # Create temp file
        tmp_file = Tempfile.new([TEMP_FILE_PATTERN, ".yaml"])
        tmp_path = tmp_file.path

        begin
          tmp_file.write(content)
          tmp_file.close

          # Edit loop: keep opening editor until valid or user quits
          loop do
            # Get file mtime before edit
            before_mtime = File.mtime(tmp_path)

            # Open editor
            unless system(@editor, tmp_path)
              raise CredentialError, "editor failed"
            end

            # Check if file was modified
            after_mtime = File.mtime(tmp_path)
            if after_mtime == before_mtime
              puts "No changes made, aborting."
              return
            end

            # Read edited content
            edited_content = File.read(tmp_path)

            # Validate
            validation_error = validate(edited_content)
            if validation_error
              puts "\n\e[31mValidation failed:\e[0m #{validation_error}"
              puts "\nPress Enter to re-edit, or Ctrl+C to abort..."
              $stdin.gets
              next
            end

            # Valid: save
            if is_first_time
              @manager.initialize_credentials(edited_content)
            else
              @manager.write(edited_content)
            end

            puts "\e[32mCredentials saved:\e[0m #{@manager.encrypted_path}"
            return
          end
        ensure
          tmp_file.close
          tmp_file.unlink
        end
      end

      # Print the decrypted credentials to stdout
      def show
        unless @manager.exists?
          raise CredentialError, "credentials file not found: #{@manager.encrypted_path}\nRun 'nvoi credentials edit' to create one"
        end

        content = @manager.read
        print content
      end

      private

        def validate(content)
          # First: basic YAML parse
          begin
            data = YAML.safe_load(content, permitted_classes: [Symbol])
          rescue Psych::SyntaxError => e
            return "invalid YAML syntax: #{e.message}"
          end

          return "config must be a hash" unless data.is_a?(Hash)

          # Second: validate required fields
          validate_required_fields(data)
        end

        def validate_required_fields(cfg)
          app = cfg["application"]
          return "application section is required" unless app.is_a?(Hash)

          # Application name
          return "application.name is required" if app["name"].nil? || app["name"].to_s.empty?

          # Environment
          return "application.environment is required" if app["environment"].nil? || app["environment"].to_s.empty?

          # Domain provider
          domain_provider = app["domain_provider"]
          return "application.domain_provider.cloudflare is required" unless domain_provider&.dig("cloudflare")

          cf = domain_provider["cloudflare"]
          return "application.domain_provider.cloudflare.api_token is required" if cf["api_token"].nil? || cf["api_token"].to_s.empty?
          return "application.domain_provider.cloudflare.account_id is required" if cf["account_id"].nil? || cf["account_id"].to_s.empty?

          # Compute provider
          compute_provider = app["compute_provider"]
          has_compute = compute_provider&.dig("hetzner") || compute_provider&.dig("aws")
          return "compute_provider (hetzner or aws) is required" unless has_compute

          if (h = compute_provider&.dig("hetzner"))
            return "application.compute_provider.hetzner.api_token is required" if h["api_token"].nil? || h["api_token"].to_s.empty?
            return "application.compute_provider.hetzner.server_type is required" if h["server_type"].nil? || h["server_type"].to_s.empty?
            return "application.compute_provider.hetzner.server_location is required" if h["server_location"].nil? || h["server_location"].to_s.empty?
          end

          if (a = compute_provider&.dig("aws"))
            return "application.compute_provider.aws.access_key_id is required" if a["access_key_id"].nil? || a["access_key_id"].to_s.empty?
            return "application.compute_provider.aws.secret_access_key is required" if a["secret_access_key"].nil? || a["secret_access_key"].to_s.empty?
            return "application.compute_provider.aws.region is required" if a["region"].nil? || a["region"].to_s.empty?
            return "application.compute_provider.aws.instance_type is required" if a["instance_type"].nil? || a["instance_type"].to_s.empty?
          end

          # Servers (if any services defined)
          servers = app["servers"] || {}
          app_services = app["app"] || {}
          database = app["database"]
          services = app["services"] || {}

          has_services = !app_services.empty? || database || !services.empty?
          return "servers must be defined when deploying services" if has_services && servers.empty?

          defined_servers = servers.keys.to_set

          # Validate app services
          app_services.each do |service_name, svc|
            next unless svc

            return "app.#{service_name}.servers is required" if svc["servers"].nil? || svc["servers"].empty?

            svc["servers"].each do |ref|
              return "app.#{service_name} references undefined server: #{ref}" unless defined_servers.include?(ref)
            end
          end

          # Validate database
          if database
            return "database.servers is required" if database["servers"].nil? || database["servers"].empty?

            database["servers"].each do |ref|
              return "database references undefined server: #{ref}" unless defined_servers.include?(ref)
            end

            db_error = validate_database_secrets(database)
            return db_error if db_error
          end

          # Validate SSH keys
          ssh_keys = app["ssh_keys"]
          return "application.ssh_keys is required" unless ssh_keys.is_a?(Hash)
          return "application.ssh_keys.private_key is required" if ssh_keys["private_key"].nil? || ssh_keys["private_key"].to_s.strip.empty?
          return "application.ssh_keys.public_key is required" if ssh_keys["public_key"].nil? || ssh_keys["public_key"].to_s.strip.empty?

          nil
        end

        def validate_database_secrets(db)
          adapter = db["adapter"]&.downcase

          case adapter
          when "postgres", "postgresql"
            %w[POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB].each do |key|
              return "database.secrets.#{key} is required for postgres" unless db.dig("secrets", key)
            end
          when "mysql"
            %w[MYSQL_USER MYSQL_PASSWORD MYSQL_DATABASE].each do |key|
              return "database.secrets.#{key} is required for mysql" unless db.dig("secrets", key)
            end
          when "sqlite3"
            # SQLite doesn't require secrets
          when nil, ""
            return "database.adapter is required"
          end

          nil
        end

        def default_template
          # Generate SSH keypair for first-time setup
          private_key, public_key = Config::SSHKeyLoader.generate_keypair

          <<~YAML
          # NVOI Deployment Configuration
          # This file is encrypted - never commit deploy.key!

          application:
            name: myapp
            environment: production

            domain_provider:
              cloudflare:
                api_token: YOUR_CLOUDFLARE_API_TOKEN
                account_id: YOUR_CLOUDFLARE_ACCOUNT_ID

            compute_provider:
              hetzner:
                api_token: YOUR_HETZNER_API_TOKEN
                server_type: cx22
                server_location: fsn1

            servers:
              master:
                type: cx22
                location: fsn1

            keep_count: 2

            app:
              web:
                servers: [master]
                domain: example.com
                subdomain: app
                port: 3000
                healthcheck:
                  type: http
                  path: /health
                  port: 3000

            # database:
            #   servers: [master]
            #   adapter: postgres
            #   image: postgres:16-alpine
            #   volume: postgres_data
            #   secrets:
            #     POSTGRES_DB: myapp_production
            #     POSTGRES_USER: myapp
            #     POSTGRES_PASSWORD: YOUR_DB_PASSWORD

            env:
              # Add environment variables here
              # RAILS_ENV: production

            secrets:
              # Add secrets here (will be injected as env vars)
              # SECRET_KEY_BASE: YOUR_SECRET_KEY_BASE

            # SSH keys (auto-generated, do not modify)
            ssh_keys:
              private_key: |
          #{private_key.lines.map { |l| "        #{l}" }.join}
              public_key: #{public_key}
        YAML
        end
    end
  end
end
