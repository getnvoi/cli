# frozen_string_literal: true

require "tempfile"
require "set"

module Nvoi
  class Cli
    module Credentials
      module Edit
        # Command handles editing encrypted credentials
        class Command
          DEFAULT_ENCRYPTED_FILE = "deploy.enc"
          DEFAULT_KEY_FILE = "deploy.key"
          DEFAULT_EDITOR = "vim"
          TEMP_FILE_PATTERN = "nvoi-credentials-"

          def initialize(options)
            @options = options
            @log = Nvoi.logger
            @editor = ENV["EDITOR"] || DEFAULT_EDITOR
          end

          def run
            @log.info "Credentials Editor"

            working_dir = resolve_working_dir
            enc_path = resolve_enc_path(working_dir)
            is_first_time = !File.exist?(enc_path)

            manager = if is_first_time
              @log.info "Creating new encrypted credentials file"
              Utils::CredentialStore.for_init(working_dir)
            else
              Utils::CredentialStore.new(working_dir, @options[:credentials], @options[:master_key])
            end

            # Get initial content
            content = if is_first_time
              default_template
            else
              manager.read
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
                  raise Errors::CredentialError, "editor failed"
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
                  manager.initialize_credentials(edited_content)
                else
                  manager.write(edited_content)
                end

                puts "\e[32mCredentials saved:\e[0m #{manager.encrypted_path}"
                break
              end
            ensure
              tmp_file.close rescue nil
              tmp_file.unlink rescue nil
            end

            # Update .gitignore on first run
            if manager.key_path
              begin
                update_gitignore(working_dir)
                @log.info "Added %s to .gitignore", DEFAULT_KEY_FILE
              rescue StandardError => e
                @log.warning "Failed to update .gitignore: %s", e.message
              end

              @log.success "Master key saved to: %s", manager.key_path
              @log.warning "Keep this key safe! You cannot decrypt credentials without it."
            end
          end

          def set(path, value)
            @log.info "Setting credential value"

            working_dir = resolve_working_dir
            manager = Utils::CredentialStore.new(working_dir, @options[:credentials], @options[:master_key])

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

            @log.success "Updated: %s = %s", path, value
          end

          private

            def resolve_working_dir
              wd = @options[:dir]
              if wd.blank? || wd == "."
                Dir.pwd
              else
                File.expand_path(wd)
              end
            end

            def resolve_enc_path(working_dir)
              enc_path = @options[:credentials]
              return File.join(working_dir, DEFAULT_ENCRYPTED_FILE) if enc_path.blank?

              enc_path
            end

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
              return "application.name is required" if app["name"].blank?

              # Environment
              return "application.environment is required" if app["environment"].blank?

              # Domain provider
              domain_provider = app["domain_provider"]
              return "application.domain_provider.cloudflare is required" unless domain_provider&.dig("cloudflare")

              cf = domain_provider["cloudflare"]
              return "application.domain_provider.cloudflare.api_token is required" if cf["api_token"].blank?
              return "application.domain_provider.cloudflare.account_id is required" if cf["account_id"].blank?

              # Compute provider
              compute_provider = app["compute_provider"]
              has_compute = compute_provider&.dig("hetzner") || compute_provider&.dig("aws") || compute_provider&.dig("scaleway")
              return "compute_provider (hetzner, aws, or scaleway) is required" unless has_compute

              if (h = compute_provider&.dig("hetzner"))
                return "application.compute_provider.hetzner.api_token is required" if h["api_token"].blank?
                return "application.compute_provider.hetzner.server_type is required" if h["server_type"].blank?
                return "application.compute_provider.hetzner.server_location is required" if h["server_location"].blank?
                return "application.compute_provider.hetzner.architecture is required" if h["architecture"].blank?
              end

              if (a = compute_provider&.dig("aws"))
                return "application.compute_provider.aws.access_key_id is required" if a["access_key_id"].blank?
                return "application.compute_provider.aws.secret_access_key is required" if a["secret_access_key"].blank?
                return "application.compute_provider.aws.region is required" if a["region"].blank?
                return "application.compute_provider.aws.instance_type is required" if a["instance_type"].blank?
                return "application.compute_provider.aws.architecture is required" if a["architecture"].blank?
              end

              if (s = compute_provider&.dig("scaleway"))
                return "application.compute_provider.scaleway.secret_key is required" if s["secret_key"].blank?
                return "application.compute_provider.scaleway.project_id is required" if s["project_id"].blank?
                return "application.compute_provider.scaleway.server_type is required" if s["server_type"].blank?
                return "application.compute_provider.scaleway.architecture is required" if s["architecture"].blank?
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

                return "app.#{service_name}.servers is required" if svc["servers"].to_a.empty?

                svc["servers"].each do |ref|
                  return "app.#{service_name} references undefined server: #{ref}" unless defined_servers.include?(ref)
                end
              end

              # Validate database
              if database
                return "database.servers is required" if database["servers"].to_a.empty?

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
              url = db["url"]

              return "database.adapter is required" if adapter.blank?

              # URL takes precedence - if provided, no secrets needed
              has_url = !url.blank?

              case adapter
              when "postgres", "postgresql"
                return nil if has_url

                %w[POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB].each do |key|
                  return "database.secrets.#{key} is required for postgres (or provide database.url)" unless db.dig("secrets", key)
                end
              when "mysql"
                return nil if has_url

                %w[MYSQL_USER MYSQL_PASSWORD MYSQL_DATABASE].each do |key|
                  return "database.secrets.#{key} is required for mysql (or provide database.url)" unless db.dig("secrets", key)
                end
              when "sqlite", "sqlite3"
                # SQLite doesn't require secrets - path can be inferred from url, mount, or defaults
              else
                return "unsupported database adapter: #{adapter}"
              end

              nil
            end

            def default_template
              # Generate SSH keypair for first-time setup
              private_key, public_key = Utils::ConfigLoader.generate_keypair

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
                    architecture: x86

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
                #   url: postgres://myapp:YOUR_DB_PASSWORD@localhost:5432/myapp_production
                #   image: postgres:16-alpine
                #
                # Or for SQLite (no container needed):
                # database:
                #   servers: [master]
                #   adapter: sqlite3
                #   mount:
                #     db: /app/data

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

            def update_gitignore(working_dir)
              gitignore_path = File.join(working_dir, ".gitignore")
              existing = File.exist?(gitignore_path) ? File.read(gitignore_path) : ""

              return if existing.include?(DEFAULT_KEY_FILE)

              File.open(gitignore_path, "a") do |f|
                f.puts "" unless existing.end_with?("\n") || existing.empty?
                f.puts "# Nvoi master key - DO NOT COMMIT"
                f.puts DEFAULT_KEY_FILE
              end
            end
        end
      end
    end
  end
end
