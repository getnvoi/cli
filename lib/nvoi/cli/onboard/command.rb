# frozen_string_literal: true

require "tty-prompt"
require "tty-box"
require "tty-spinner"
require "tty-table"

module Nvoi
  class Cli
    module Onboard
      # Interactive onboarding wizard for quick setup
      class Command
        MAX_RETRIES = 3

        def initialize(prompt: nil)
          @prompt = prompt || TTY::Prompt.new
          @data = { "application" => {} }
          @test_mode = prompt&.input.is_a?(StringIO)
        end

        def run
          show_welcome

          step_app_name
          step_compute_provider
          step_domain_provider
          step_apps
          step_database
          step_env

          show_summary
          save_config if confirm_save?

          show_next_steps
        rescue TTY::Reader::InputInterrupt
          puts "\n\nSetup cancelled."
          exit 1
        end

        private

          # ─────────────────────────────────────────────────────────────────
          # Welcome
          # ─────────────────────────────────────────────────────────────────

          def show_welcome
            box = TTY::Box.frame(
              "NVOI Quick Setup",
              padding: [0, 2],
              align: :center,
              border: :light
            )
            puts box
            puts
          end

          # ─────────────────────────────────────────────────────────────────
          # Step 1: App Name
          # ─────────────────────────────────────────────────────────────────

          def step_app_name
            name = @prompt.ask("Application name:") do |q|
              q.required true
              q.validate(/\A[a-z0-9_-]+\z/i, "Only letters, numbers, dashes, underscores")
            end
            @data["application"]["name"] = name
          end

          # ─────────────────────────────────────────────────────────────────
          # Step 2: Compute Provider
          # ─────────────────────────────────────────────────────────────────

          def step_compute_provider
            puts
            puts section("Compute Provider")

            provider = @prompt.select("Select provider:") do |menu|
              menu.choice "Hetzner (recommended)", :hetzner
              menu.choice "AWS", :aws
              menu.choice "Scaleway", :scaleway
            end

            case provider
            when :hetzner then setup_hetzner
            when :aws then setup_aws
            when :scaleway then setup_scaleway
            end
          end

          def setup_hetzner
            token = prompt_with_retry("Hetzner API Token:", mask: true) do |t|
              client = External::Cloud::Hetzner.new(t)
              client.validate_credentials
              @hetzner_client = client
            end

            types, locations = with_spinner("Fetching options...") do
              [@hetzner_client.list_server_types, @hetzner_client.list_locations]
            end

            type_choices = types.sort_by { |t| t[:name] }.map do |t|
              price = t[:price] ? " - #{t[:price]}/mo" : ""
              { name: "#{t[:name]} (#{t[:cores]} vCPU, #{t[:memory] / 1024}GB#{price})", value: t[:name] }
            end

            location_choices = locations.map do |l|
              { name: "#{l[:name]} (#{l[:city]}, #{l[:country]})", value: l[:name] }
            end

            server_type = @prompt.select("Server type:", type_choices, per_page: 10)
            location = @prompt.select("Location:", location_choices)

            @data["application"]["compute_provider"] = {
              "hetzner" => {
                "api_token" => token,
                "server_type" => server_type,
                "server_location" => location
              }
            }
          end

          def setup_aws
            access_key = prompt_with_retry("AWS Access Key ID:") do |k|
              raise Errors::ValidationError, "Invalid format" unless k.match?(/\AAKIA/)
            end

            secret_key = @prompt.mask("AWS Secret Access Key:")

            # Get regions first with temp client
            temp_client = External::Cloud::Aws.new(access_key, secret_key, "us-east-1")
            regions = with_spinner("Validating credentials...") do
              temp_client.validate_credentials
              temp_client.list_regions
            end

            region_choices = regions.map { |r| r[:name] }.sort
            region = @prompt.select("Region:", region_choices, per_page: 10, filter: true)

            # Now get instance types for selected region
            client = External::Cloud::Aws.new(access_key, secret_key, region)
            types = client.list_instance_types

            type_choices = types.map do |t|
              mem = t[:memory] ? " #{t[:memory] / 1024}GB" : ""
              { name: "#{t[:name]} (#{t[:vcpus]} vCPU#{mem})", value: t[:name] }
            end

            instance_type = @prompt.select("Instance type:", type_choices)

            @data["application"]["compute_provider"] = {
              "aws" => {
                "access_key_id" => access_key,
                "secret_access_key" => secret_key,
                "region" => region,
                "instance_type" => instance_type
              }
            }
          end

          def setup_scaleway
            secret_key = prompt_with_retry("Scaleway Secret Key:", mask: true)
            project_id = @prompt.ask("Scaleway Project ID:") { |q| q.required true }

            # Get zones (static list)
            temp_client = External::Cloud::Scaleway.new(secret_key, project_id)
            zones = temp_client.list_zones

            zone_choices = zones.map { |z| { name: "#{z[:name]} (#{z[:city]})", value: z[:name] } }
            zone = @prompt.select("Zone:", zone_choices)

            # Validate and get server types
            client = External::Cloud::Scaleway.new(secret_key, project_id, zone:)
            types = with_spinner("Validating credentials...") do
              client.validate_credentials
              client.list_server_types
            end

            type_choices = types.map do |t|
              { name: "#{t[:name]} (#{t[:cores]} cores)", value: t[:name] }
            end

            server_type = @prompt.select("Server type:", type_choices, per_page: 10, filter: true)

            @data["application"]["compute_provider"] = {
              "scaleway" => {
                "secret_key" => secret_key,
                "project_id" => project_id,
                "zone" => zone,
                "server_type" => server_type
              }
            }
          end

          # ─────────────────────────────────────────────────────────────────
          # Step 3: Domain Provider
          # ─────────────────────────────────────────────────────────────────

          def step_domain_provider
            puts
            puts section("Domain Provider")

            setup = @prompt.yes?("Configure Cloudflare for domains/tunnels?")
            return unless setup

            token = prompt_with_retry("Cloudflare API Token:", mask: true)
            account_id = @prompt.ask("Cloudflare Account ID:") { |q| q.required true }

            @cloudflare_client = External::Dns::Cloudflare.new(token, account_id)

            @cloudflare_zones = with_spinner("Fetching domains...") do
              @cloudflare_client.validate_credentials
              @cloudflare_client.list_zones.select { |z| z[:status] == "active" }
            end

            if @cloudflare_zones.empty?
              warn "No active domains found in Cloudflare account"
            end

            @data["application"]["domain_provider"] = {
              "cloudflare" => {
                "api_token" => token,
                "account_id" => account_id
              }
            }
          end

          # ─────────────────────────────────────────────────────────────────
          # Step 4: Apps (loop)
          # ─────────────────────────────────────────────────────────────────

          def step_apps
            puts
            puts section("Applications")

            # Ensure we have a server
            @data["application"]["servers"] ||= {}
            @data["application"]["servers"]["main"] = { "master" => true, "count" => 1 }

            @data["application"]["app"] ||= {}

            loop do
              name = @prompt.ask("App name:") { |q| q.required true }
              command = @prompt.ask("Run command:", default: "bundle exec puma -C config/puma.rb")
              port = @prompt.ask("Port:", default: "3000", convert: :int)

              app_config = {
                "servers" => ["main"],
                "command" => command,
                "port" => port
              }

              # Domain selection from Cloudflare if configured
              if @cloudflare_zones&.any?
                domain, subdomain = prompt_domain_selection
                if domain
                  app_config["domain"] = domain
                  app_config["subdomain"] = subdomain unless subdomain.to_s.empty?
                end
              end

              pre_run = @prompt.ask("Pre-run command (e.g. migrations):")
              app_config["pre_run_command"] = pre_run unless pre_run.to_s.empty?

              @data["application"]["app"][name] = app_config

              break unless @prompt.yes?("Add another app?")
            end
          end

          def prompt_domain_selection
            domain_choices = @cloudflare_zones.map { |z| { name: z[:name], value: z } }
            domain_choices << { name: "Skip (no domain)", value: nil }

            selected = @prompt.select("Domain:", domain_choices)
            return [nil, nil] unless selected

            zone_id = selected[:id]
            domain = selected[:name]

            # Prompt for subdomain with validation
            subdomain = prompt_subdomain(zone_id, domain)

            [domain, subdomain]
          end

          def prompt_subdomain(zone_id, domain)
            loop do
              subdomain = @prompt.ask("Subdomain (leave blank for root #{domain}):")
              subdomain = subdomain.to_s.strip.downcase

              # Validate subdomain format if provided
              if !subdomain.empty? && !subdomain.match?(/\A[a-z0-9]([a-z0-9-]*[a-z0-9])?\z/)
                error("Invalid subdomain format. Use lowercase letters, numbers, and hyphens.")
                next
              end

              # Check availability
              fqdn = subdomain.empty? ? domain : "#{subdomain}.#{domain}"

              available = with_spinner("Checking #{fqdn}...") do
                @cloudflare_client.subdomain_available?(zone_id, subdomain, domain)
              end

              if available
                return subdomain
              else
                error("#{fqdn} already has a DNS record. Choose a different subdomain.")
              end
            end
          end

          # ─────────────────────────────────────────────────────────────────
          # Step 5: Database
          # ─────────────────────────────────────────────────────────────────

          def step_database
            puts
            puts section("Database")

            adapter = @prompt.select("Database:") do |menu|
              menu.choice "PostgreSQL", "postgres"
              menu.choice "MySQL", "mysql"
              menu.choice "SQLite", "sqlite3"
              menu.choice "None (skip)", nil
            end

            return unless adapter

            db_config = {
              "servers" => ["main"],
              "adapter" => adapter
            }

            case adapter
            when "postgres"
              db_name = @prompt.ask("Database name:", default: "#{@data["application"]["name"]}_production")
              user = @prompt.ask("Database user:", default: @data["application"]["name"])
              password = @prompt.mask("Database password:") { |q| q.required true }

              db_config["secrets"] = {
                "POSTGRES_DB" => db_name,
                "POSTGRES_USER" => user,
                "POSTGRES_PASSWORD" => password
              }

              # Auto-add volume
              @data["application"]["servers"]["main"]["volumes"] = {
                "postgres_data" => { "size" => 10 }
              }

            when "mysql"
              db_name = @prompt.ask("Database name:", default: "#{@data["application"]["name"]}_production")
              user = @prompt.ask("Database user:", default: @data["application"]["name"])
              password = @prompt.mask("Database password:") { |q| q.required true }

              db_config["secrets"] = {
                "MYSQL_DATABASE" => db_name,
                "MYSQL_USER" => user,
                "MYSQL_PASSWORD" => password
              }

              # Auto-add volume
              @data["application"]["servers"]["main"]["volumes"] = {
                "mysql_data" => { "size" => 10 }
              }

            when "sqlite3"
              path = @prompt.ask("Database path:", default: "/app/data/production.sqlite3")
              db_config["path"] = path
              db_config["mount"] = { "data" => "/app/data" }

              # Auto-add volume
              @data["application"]["servers"]["main"]["volumes"] = {
                "sqlite_data" => { "size" => 10 }
              }
            end

            @data["application"]["database"] = db_config
          end

          # ─────────────────────────────────────────────────────────────────
          # Step 6: Environment Variables
          # ─────────────────────────────────────────────────────────────────

          def step_env
            puts
            puts section("Environment Variables")

            @data["application"]["env"] ||= {}
            @data["application"]["secrets"] ||= {}

            # Add default
            @data["application"]["env"]["RAILS_ENV"] = "production"

            loop do
              show_env_table

              choice = @prompt.select("Action:") do |menu|
                menu.choice "Add variable", :add
                menu.choice "Add secret (masked)", :secret
                menu.choice "Done", :done
              end

              case choice
              when :add
                key = @prompt.ask("Variable name:") { |q| q.required true }
                value = @prompt.ask("Value:") { |q| q.required true }
                @data["application"]["env"][key] = value

              when :secret
                key = @prompt.ask("Secret name:") { |q| q.required true }
                value = @prompt.mask("Value:") { |q| q.required true }
                @data["application"]["secrets"][key] = value

              when :done
                break
              end
            end
          end

          def show_env_table
            return if @data["application"]["env"].empty? && @data["application"]["secrets"].empty?

            rows = []
            @data["application"]["env"].each { |k, v| rows << [k, v] }
            @data["application"]["secrets"].each { |k, _| rows << [k, "********"] }

            table = TTY::Table.new(header: %w[Key Value], rows:)
            puts table.render(:unicode, padding: [0, 1])
            puts
          end

          # ─────────────────────────────────────────────────────────────────
          # Summary & Save
          # ─────────────────────────────────────────────────────────────────

          def show_summary
            puts
            puts section("Summary")

            provider_name = @data["application"]["compute_provider"]&.keys&.first || "none"
            provider_info = case provider_name
            when "hetzner"
              cfg = @data["application"]["compute_provider"]["hetzner"]
              "#{cfg["server_type"]} @ #{cfg["server_location"]}"
            when "aws"
              cfg = @data["application"]["compute_provider"]["aws"]
              "#{cfg["instance_type"]} @ #{cfg["region"]}"
            when "scaleway"
              cfg = @data["application"]["compute_provider"]["scaleway"]
              "#{cfg["server_type"]} @ #{cfg["zone"]}"
            else
              "not configured"
            end

            domain_ok = @data["application"]["domain_provider"]&.any? ? "configured" : "not configured"

            # Build app list with domains
            app_list = @data["application"]["app"]&.map do |name, cfg|
              if cfg["domain"]
                fqdn = cfg["subdomain"] ? "#{cfg["subdomain"]}.#{cfg["domain"]}" : cfg["domain"]
                "#{name} (#{fqdn})"
              else
                name
              end
            end&.join(", ") || "none"
            db = @data["application"]["database"]&.dig("adapter") || "none"
            env_count = (@data["application"]["env"]&.size || 0) + (@data["application"]["secrets"]&.size || 0)

            rows = [
              ["Application", @data["application"]["name"]],
              ["Provider", "#{provider_name} (#{provider_info})"],
              ["Domain", "Cloudflare #{domain_ok}"],
              ["Apps", app_list],
              ["Database", db],
              ["Env/Secrets", "#{env_count} variables"]
            ]

            table = TTY::Table.new(rows:)
            puts table.render(:unicode, padding: [0, 1])
            puts
          end

          def confirm_save?
            @prompt.yes?("Save configuration?")
          end

          def save_config
            with_spinner("Generating SSH keys...") do
              # Use ConfigApi.init to generate keys and encrypt
              result = ConfigApi.init(
                name: @data["application"]["name"],
                environment: "production"
              )

              if result.failure?
                raise Errors::ConfigError, "Failed to initialize: #{result.error_message}"
              end

              # Now we need to apply all our config on top
              # Decrypt the init result, merge our data, re-encrypt
              yaml = Utils::Crypto.decrypt(result.config, result.master_key)
              init_data = YAML.safe_load(yaml, permitted_classes: [Symbol])

              # Merge our data into init_data (keep ssh_keys from init)
              init_data["application"].merge!(@data["application"])
              init_data["application"]["ssh_keys"] = YAML.safe_load(yaml)["application"]["ssh_keys"]

              # Write files
              config_path = File.join(".", Utils::DEFAULT_ENCRYPTED_FILE)
              key_path = File.join(".", Utils::DEFAULT_KEY_FILE)

              final_yaml = YAML.dump(init_data)
              encrypted = Utils::Crypto.encrypt(final_yaml, result.master_key)

              File.binwrite(config_path, encrypted)
              File.write(key_path, "#{result.master_key}\n", perm: 0o600)

              update_gitignore
            end

            puts
            success("Created #{Utils::DEFAULT_ENCRYPTED_FILE}")
            success("Created #{Utils::DEFAULT_KEY_FILE}")
          end

          def show_next_steps
            puts
            puts "Next: #{pastel.cyan("nvoi deploy")}"
          end

          # ─────────────────────────────────────────────────────────────────
          # Helpers
          # ─────────────────────────────────────────────────────────────────

          def prompt_with_retry(message, mask: false, &validation)
            retries = 0
            loop do
              value = mask ? @prompt.mask(message) : @prompt.ask(message) { |q| q.required true }

              begin
                yield(value) if block_given?
                return value
              rescue Errors::ValidationError, Errors::AuthenticationError => e
                retries += 1
                if retries >= MAX_RETRIES
                  error("Failed after #{MAX_RETRIES} attempts: #{e.message}")
                  raise
                end
                warn("#{e.message}. Please try again. (#{retries}/#{MAX_RETRIES})")
              end
            end
          end

          def section(title)
            pastel.bold("─── #{title} ───")
          end

          def with_spinner(message)
            if @test_mode
              result = yield
              return result
            end

            spinner = TTY::Spinner.new("[:spinner] #{message}", format: :dots)
            spinner.auto_spin
            begin
              result = yield
              spinner.success("done")
              result
            rescue StandardError => e
              spinner.error("failed")
              raise e
            end
          end

          def success(msg)
            puts "#{pastel.green("✓")} #{msg}"
          end

          def error(msg)
            warn "#{pastel.red("✗")} #{msg}"
          end

          def pastel
            @pastel ||= Pastel.new
          end

          def update_gitignore
            gitignore_path = ".gitignore"
            entries = ["deploy.key", ".env", ".env.*", "!.env.example"]

            existing = File.exist?(gitignore_path) ? File.read(gitignore_path) : ""
            additions = entries.reject { |e| existing.include?(e) }

            return if additions.empty?

            File.open(gitignore_path, "a") do |f|
              f.puts "" unless existing.end_with?("\n") || existing.empty?
              f.puts "# NVOI"
              additions.each { |e| f.puts e }
            end
          end
      end
    end
  end
end
