# frozen_string_literal: true

module Nvoi
  class Cli
    module Onboard
      module Steps
        # Single app form - used for add and edit
        class App
          include Onboard::Ui

          def initialize(prompt, test_mode: false)
            @prompt = prompt
            @test_mode = test_mode
          end

          # Returns [name, config] tuple
          def call(existing_name: nil, existing: nil, zones: [], cloudflare_client: nil)
            @zones = zones
            @cloudflare_client = cloudflare_client

            name = @prompt.ask("App name:", default: existing_name) { |q| q.required true }

            command = prompt_optional("Run command", existing&.dig("command"),
              placeholder: "leave blank for Docker entrypoint")

            port = prompt_optional("Port", existing&.dig("port")&.to_s,
              placeholder: "leave blank for background workers")
            port = port.to_i if port && !port.to_s.empty?

            config = { "servers" => existing&.dig("servers") || ["main"] }
            config["command"] = command unless command.to_s.empty?
            config["port"] = port if port && port.to_i > 0

            # Domain selection only if port is set and cloudflare configured
            if port && port.to_i > 0 && @zones.any?
              domain, subdomain = prompt_domain_selection
              if domain
                config["domain"] = domain
                config["subdomain"] = subdomain unless subdomain.to_s.empty?
              end
            end

            pre_run = prompt_optional("Pre-run command", existing&.dig("pre_run_command"),
              placeholder: "e.g. migrations")
            config["pre_run_command"] = pre_run unless pre_run.to_s.empty?

            [name, config]
          end

          private

            def prompt_optional(label, default, placeholder: nil)
              hint = placeholder ? " (#{placeholder})" : ""
              if default
                @prompt.ask("#{label}#{hint}:", default:)
              else
                @prompt.ask("#{label}#{hint}:")
              end
            end

            def prompt_domain_selection
              domain_choices = @zones.map { |z| { name: z[:name], value: z } }
              domain_choices << { name: "Skip (no domain)", value: nil }

              selected = @prompt.select("Domain:", domain_choices)
              return [nil, nil] unless selected

              zone_id = selected[:id]
              domain = selected[:name]
              subdomain = prompt_subdomain(zone_id, domain)

              [domain, subdomain]
            end

            def prompt_subdomain(zone_id, domain)
              loop do
                subdomain = @prompt.ask("Subdomain (leave blank for #{domain} + *.#{domain}):")
                subdomain = subdomain.to_s.strip.downcase

                if !subdomain.empty? && !subdomain.match?(/\A[a-z0-9]([a-z0-9-]*[a-z0-9])?\z/)
                  error("Invalid subdomain format. Use lowercase letters, numbers, and hyphens.")
                  next
                end

                hostnames = Utils::Namer.build_hostnames(subdomain.empty? ? nil : subdomain, domain)
                all_available = true

                hostnames.each do |hostname|
                  available = with_spinner("Checking #{hostname}...") do
                    check_subdomain = hostname == domain ? "" : hostname.sub(".#{domain}", "")
                    @cloudflare_client.subdomain_available?(zone_id, check_subdomain, domain)
                  end

                  unless available
                    error("#{hostname} already has a DNS record. Choose a different subdomain.")
                    all_available = false
                    break
                  end
                end

                return subdomain if all_available
              end
            end
        end
      end
    end
  end
end
