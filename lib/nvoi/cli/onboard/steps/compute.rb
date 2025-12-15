# frozen_string_literal: true

module Nvoi
  class Cli
    module Onboard
      module Steps
        # Collects compute provider configuration
        class Compute
          include Onboard::Ui

          PROVIDERS = [
            { name: "Hetzner (recommended)", value: :hetzner },
            { name: "AWS", value: :aws },
            { name: "Scaleway", value: :scaleway }
          ].freeze

          def initialize(prompt, test_mode: false)
            @prompt = prompt
            @test_mode = test_mode
          end

          def call(existing: nil)
            section "Compute Provider"

            provider = @prompt.select("Select provider:", PROVIDERS)

            case provider
            when :hetzner  then setup_hetzner
            when :aws      then setup_aws
            when :scaleway then setup_scaleway
            end
          end

          private

            def setup_hetzner
              token = prompt_with_retry("Hetzner API Token:", mask: true) do |t|
                client = External::Cloud::Hetzner.new(t)
                client.validate_credentials
                @client = client
              end

              types, locations = with_spinner("Fetching options...") do
                [@client.list_server_types, @client.list_locations]
              end

              # Step 1: Pick location first
              location_choices = locations.map do |l|
                { name: "#{l[:name]} (#{l[:city]}, #{l[:country]})", value: l[:name] }
              end

              location = @prompt.select("Location:", location_choices)

              # Step 2: Filter server types available at selected location
              available_types = types.select { |t| t[:locations].include?(location) }

              type_choices = available_types.sort_by { |t| t[:name] }.map do |t|
                price = price_for_location(t[:prices], location)
                price_str = price ? " - €#{price}/mo" : ""
                memory_gb = t[:memory].to_f.round(1)
                cpu_info = cpu_label(t[:cpu_type], t[:architecture])
                { name: "#{t[:name]} (#{t[:cores]} vCPU, #{memory_gb}GB, #{cpu_info}#{price_str})", value: t[:name] }
              end

              server_type = @prompt.select("Server type:", type_choices, per_page: 10, filter: true)

              # Get architecture for selected server type
              selected_type = available_types.find { |t| t[:name] == server_type }
              arch = selected_type&.dig(:architecture) || "x86"

              {
                "hetzner" => {
                  "api_token" => token,
                  "server_type" => server_type,
                  "server_location" => location,
                  "architecture" => arch
                }
              }
            end

            def price_for_location(prices, location)
              return nil unless prices

              price_entry = prices.find { |p| p["location"] == location }
              return nil unless price_entry

              gross = price_entry.dig("price_monthly", "gross")
              return nil unless gross

              gross.to_f.round(2)
            end

            def cpu_label(cpu_type, architecture)
              arch = architecture == "arm" ? "ARM" : "x86"
              type = cpu_type == "dedicated" ? "dedicated" : "shared"
              "#{arch}/#{type}"
            end

            def setup_aws
              access_key = prompt_with_retry("AWS Access Key ID:") do |k|
                raise Errors::ValidationError, "Invalid format" unless k.match?(/\AAKIA/)
              end

              secret_key = @prompt.mask("AWS Secret Access Key:")

              temp_client = External::Cloud::Aws.new(access_key, secret_key, "us-east-1")
              regions = with_spinner("Validating credentials...") do
                temp_client.validate_credentials
                temp_client.list_regions
              end

              region_choices = regions.map { |r| r[:name] }.sort
              region = @prompt.select("Region:", region_choices, per_page: 10, filter: true)

              client = External::Cloud::Aws.new(access_key, secret_key, region)
              types = client.list_instance_types

              type_choices = types.map do |t|
                mem = t[:memory] ? " #{t[:memory] / 1024}GB" : ""
                arch_label = t[:architecture] == "arm64" ? " ARM" : ""
                { name: "#{t[:name]} (#{t[:vcpus]} vCPU#{mem}#{arch_label})", value: t[:name] }
              end

              instance_type = @prompt.select("Instance type:", type_choices)

              # Get architecture for selected instance type
              selected_type = types.find { |t| t[:name] == instance_type }
              arch = selected_type&.dig(:architecture) || "x86"

              {
                "aws" => {
                  "access_key_id" => access_key,
                  "secret_access_key" => secret_key,
                  "region" => region,
                  "instance_type" => instance_type,
                  "architecture" => arch
                }
              }
            end

            def setup_scaleway
              secret_key = prompt_with_retry("Scaleway Secret Key:", mask: true)
              project_id = @prompt.ask("Scaleway Project ID:") { |q| q.required true }

              temp_client = External::Cloud::Scaleway.new(secret_key, project_id)
              zones = temp_client.list_zones

              zone_choices = zones.map { |z| { name: "#{z[:name]} (#{z[:city]})", value: z[:name] } }
              zone = @prompt.select("Zone:", zone_choices)

              client = External::Cloud::Scaleway.new(secret_key, project_id, zone:)
              types = with_spinner("Validating credentials...") do
                client.validate_credentials
                client.list_server_types
              end

              type_choices = types.map do |t|
                arch_label = t[:architecture] == "arm64" ? " ARM" : ""
                { name: "#{t[:name]} (#{t[:cores]} cores#{arch_label})", value: t[:name] }
              end

              server_type = @prompt.select("Server type:", type_choices, per_page: 10, filter: true)

              # Get architecture for selected server type
              selected_type = types.find { |t| t[:name] == server_type }
              arch = selected_type&.dig(:architecture) || "x86"

              {
                "scaleway" => {
                  "secret_key" => secret_key,
                  "project_id" => project_id,
                  "zone" => zone,
                  "server_type" => server_type,
                  "architecture" => arch
                }
              }
            end
        end
      end
    end
  end
end
