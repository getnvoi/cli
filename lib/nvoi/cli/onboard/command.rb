# frozen_string_literal: true

require "stringio"
require "tty-prompt"
require "nvoi/utils/credential_store"

module Nvoi
  class Cli
    module Onboard
      # Interactive onboarding wizard for quick setup
      class Command
        include Onboard::Ui

        SUMMARY_ACTIONS = [
          { name: "Save configuration", value: :save },
          { name: "Edit application name", value: :app_name },
          { name: "Edit compute provider", value: :compute },
          { name: "Edit domain provider", value: :domain },
          { name: "Edit apps", value: :apps },
          { name: "Edit database", value: :database },
          { name: "Edit environment variables", value: :env },
          { name: "Start over", value: :restart },
          { name: "Cancel (discard)", value: :cancel }
        ].freeze

        def initialize(prompt: nil)
          @prompt = prompt || TTY::Prompt.new
          @test_mode = prompt&.input.is_a?(StringIO)
          @data = default_data
          @domain_step = nil
        end

        def run
          show_welcome
          collect_all
          summary_loop
          show_next_steps
        rescue TTY::Reader::InputInterrupt
          puts "\n\nSetup cancelled."
          exit 1
        end

        private

          def default_data
            {
              name: nil,
              compute: nil,
              domain: nil,
              apps: {},
              database: nil,
              volumes: nil,
              env: {},
              secrets: {}
            }
          end

          def collect_all
            @data[:name] = Steps::AppName.new(@prompt, test_mode: @test_mode).call
            @data[:compute] = Steps::Compute.new(@prompt, test_mode: @test_mode).call

            @domain_step = Steps::Domain.new(@prompt, test_mode: @test_mode)
            @data[:domain] = @domain_step.call

            collect_apps
            collect_database
            collect_env
          end

          def collect_apps
            section "Applications"

            loop do
              name, config = Steps::App.new(@prompt, test_mode: @test_mode).call(
                zones: @domain_step&.zones || [],
                cloudflare_client: @domain_step&.client
              )
              @data[:apps][name] = config

              break unless @prompt.yes?("Add another app?")
            end
          end

          def collect_database
            db_config, volume_config = Steps::Database.new(@prompt, test_mode: @test_mode)
              .call(app_name: @data[:name])

            @data[:database] = db_config
            @data[:volumes] = volume_config
          end

          def collect_env
            @data[:env], @data[:secrets] = Steps::Env.new(@prompt, test_mode: @test_mode)
              .call(existing_env: @data[:env], existing_secrets: @data[:secrets])
          end

          # ─── Summary Loop ───

          def summary_loop
            loop do
              show_summary

              case @prompt.select("What would you like to do?", SUMMARY_ACTIONS)
              when :save
                save_config
                return
              when :cancel
                return if @prompt.yes?("Discard all changes?")
              when :app_name
                @data[:name] = Steps::AppName.new(@prompt, test_mode: @test_mode)
                  .call(existing: @data[:name])
              when :compute
                @data[:compute] = Steps::Compute.new(@prompt, test_mode: @test_mode).call
              when :domain
                @domain_step = Steps::Domain.new(@prompt, test_mode: @test_mode)
                @data[:domain] = @domain_step.call
              when :apps
                edit_apps
              when :database
                collect_database
              when :env
                collect_env
              when :restart
                restart_wizard
              end
            end
          end

          def edit_apps
            loop do
              choices = @data[:apps].keys.map { |name| { name:, value: name } }
              choices << { name: "Add new app", value: :add }
              choices << { name: "Done", value: :done }

              selected = @prompt.select("Apps:", choices)

              case selected
              when :add
                name, config = Steps::App.new(@prompt, test_mode: @test_mode).call(
                  zones: @domain_step&.zones || [],
                  cloudflare_client: @domain_step&.client
                )
                @data[:apps][name] = config
              when :done
                return
              else
                edit_single_app(selected)
              end
            end
          end

          def edit_single_app(name)
            action = @prompt.select("#{name}:") do |menu|
              menu.choice "Edit", :edit
              menu.choice "Delete", :delete
              menu.choice "Back", :back
            end

            case action
            when :edit
              new_name, config = Steps::App.new(@prompt, test_mode: @test_mode).call(
                existing_name: name,
                existing: @data[:apps][name],
                zones: @domain_step&.zones || [],
                cloudflare_client: @domain_step&.client
              )
              @data[:apps].delete(name) if new_name != name
              @data[:apps][new_name] = config
            when :delete
              @data[:apps].delete(name) if @prompt.yes?("Delete #{name}?")
            end
          end

          def restart_wizard
            return unless @prompt.yes?("This will clear all data. Continue?")

            @data = default_data
            @domain_step = nil
            collect_all
          end

          # ─── Summary Display ───

          def show_welcome
            box "NVOI Quick Setup"
          end

          def show_summary
            section "Summary"

            rows = [
              ["Application", @data[:name]],
              ["Provider", format_provider],
              ["Domain", format_domain],
              ["Apps", format_apps],
              ["Database", @data[:database]&.dig("adapter") || "none"],
              ["Env/Secrets", "#{@data[:env].size + @data[:secrets].size} variables"]
            ]

            table(rows:)
          end

          def format_provider
            return "not configured" unless @data[:compute]

            provider_name = @data[:compute].keys.first
            cfg = @data[:compute][provider_name]

            info = case provider_name
            when "hetzner"  then "#{cfg["server_type"]} @ #{cfg["server_location"]}"
            when "aws"      then "#{cfg["instance_type"]} @ #{cfg["region"]}"
            when "scaleway" then "#{cfg["server_type"]} @ #{cfg["zone"]}"
            else "configured"
            end

            "#{provider_name} (#{info})"
          end

          def format_domain
            @data[:domain] ? "Cloudflare configured" : "Cloudflare not configured"
          end

          def format_apps
            return "none" if @data[:apps].empty?

            @data[:apps].map do |name, cfg|
              if cfg["domain"]
                fqdn = cfg["subdomain"] ? "#{cfg["subdomain"]}.#{cfg["domain"]}" : cfg["domain"]
                "#{name} (#{fqdn})"
              else
                name
              end
            end.join(", ")
          end

          # ─── Save ───

          def save_config
            with_spinner("Generating SSH keys...") do
              result = Configuration::Builder.init(name: @data[:name], environment: "production")

              if result.failure?
                raise Errors::ConfigError, "Failed to initialize: #{result.error_message}"
              end

              yaml = Utils::Crypto.decrypt(result.config, result.master_key)
              init_data = YAML.safe_load(yaml, permitted_classes: [Symbol])

              final_data = build_final_config(init_data)
              write_config_files(final_data, result.master_key)
            end

            puts
            success "Created #{Utils::DEFAULT_ENCRYPTED_FILE}"
            success "Created #{Utils::DEFAULT_KEY_FILE}"
          end

          def build_final_config(init_data)
            app_data = {
              "name" => @data[:name],
              "ssh_keys" => init_data["application"]["ssh_keys"],
              "servers" => { "main" => { "master" => true, "count" => 1 } },
              "app" => @data[:apps],
              "env" => @data[:env],
              "secrets" => @data[:secrets]
            }

            app_data["compute_provider"] = @data[:compute] if @data[:compute]
            app_data["domain_provider"] = @data[:domain] if @data[:domain]
            app_data["database"] = @data[:database] if @data[:database]

            if @data[:volumes]
              app_data["servers"]["main"]["volumes"] = @data[:volumes]
            end

            { "application" => app_data }
          end

          def write_config_files(data, master_key)
            config_path = File.join(".", Utils::DEFAULT_ENCRYPTED_FILE)
            key_path = File.join(".", Utils::DEFAULT_KEY_FILE)

            final_yaml = YAML.dump(data)
            encrypted = Utils::Crypto.encrypt(final_yaml, master_key)

            File.binwrite(config_path, encrypted)
            File.write(key_path, "#{master_key}\n", perm: 0o600)

            update_gitignore
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

          def show_next_steps
            puts
            puts "Next: #{pastel.cyan("nvoi deploy")}"
          end
      end
    end
  end
end
