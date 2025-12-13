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

              type_choices = types.sort_by { |t| t[:name] }.map do |t|
                price = t[:price] ? " - #{t[:price]}/mo" : ""
                { name: "#{t[:name]} (#{t[:cores]} vCPU, #{t[:memory] / 1024}GB#{price})", value: t[:name] }
              end

              location_choices = locations.map do |l|
                { name: "#{l[:name]} (#{l[:city]}, #{l[:country]})", value: l[:name] }
              end

              server_type = @prompt.select("Server type:", type_choices, per_page: 10)
              location = @prompt.select("Location:", location_choices)

              {
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
                { name: "#{t[:name]} (#{t[:vcpus]} vCPU#{mem})", value: t[:name] }
              end

              instance_type = @prompt.select("Instance type:", type_choices)

              {
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
                { name: "#{t[:name]} (#{t[:cores]} cores)", value: t[:name] }
              end

              server_type = @prompt.select("Server type:", type_choices, per_page: 10, filter: true)

              {
                "scaleway" => {
                  "secret_key" => secret_key,
                  "project_id" => project_id,
                  "zone" => zone,
                  "server_type" => server_type
                }
              }
            end
        end
      end
    end
  end
end
