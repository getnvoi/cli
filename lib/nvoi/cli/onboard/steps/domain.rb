# frozen_string_literal: true

module Nvoi
  class Cli
    module Onboard
      module Steps
        # Collects domain provider (Cloudflare) configuration
        class Domain
          include UI

          attr_reader :client, :zones

          def initialize(prompt, test_mode: false)
            @prompt = prompt
            @test_mode = test_mode
            @client = nil
            @zones = []
          end

          def call(existing: nil)
            section "Domain Provider"

            return nil unless @prompt.yes?("Configure Cloudflare for domains/tunnels?")

            token = prompt_with_retry("Cloudflare API Token:", mask: true)
            account_id = @prompt.ask("Cloudflare Account ID:") { |q| q.required true }

            @client = External::Dns::Cloudflare.new(token, account_id)

            @zones = with_spinner("Fetching domains...") do
              @client.validate_credentials
              @client.list_zones.select { |z| z[:status] == "active" }
            end

            warn "No active domains found in Cloudflare account" if @zones.empty?

            {
              "cloudflare" => {
                "api_token" => token,
                "account_id" => account_id
              }
            }
          end
        end
      end
    end
  end
end
