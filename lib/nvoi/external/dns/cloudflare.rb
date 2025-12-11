# frozen_string_literal: true

require "faraday"
require "base64"
require "securerandom"

module Nvoi
  module External
    module Dns
      # Cloudflare handles Cloudflare API operations for DNS and tunnels
      class Cloudflare
        BASE_URL = "https://api.cloudflare.com/client/v4"

        attr_reader :account_id

        def initialize(token, account_id)
          @token = token
          @account_id = account_id
          @conn = Faraday.new(url: BASE_URL) do |f|
            f.request :json
            f.response :json
            f.adapter Faraday.default_adapter
          end
        end

        # Tunnel operations

        def create_tunnel(name)
          url = "accounts/#{@account_id}/cfd_tunnel"
          tunnel_secret = generate_tunnel_secret

          response = post(url, {
            name:,
            tunnel_secret:,
            config_src: "cloudflare"
          })

          result = response["result"]
          Objects::Tunnel::Record.new(
            id: result["id"],
            name: result["name"],
            token: result["token"]
          )
        end

        def find_tunnel(name)
          url = "accounts/#{@account_id}/cfd_tunnel"
          response = get(url, { name:, is_deleted: false })

          results = response["result"]
          return nil if results.nil? || results.empty?

          result = results[0]
          Objects::Tunnel::Record.new(
            id: result["id"],
            name: result["name"],
            token: result["token"]
          )
        end

        def get_tunnel_token(tunnel_id)
          url = "accounts/#{@account_id}/cfd_tunnel/#{tunnel_id}/token"
          response = get(url)
          response["result"]
        end

        def update_tunnel_configuration(tunnel_id, hostname, service_url)
          url = "accounts/#{@account_id}/cfd_tunnel/#{tunnel_id}/configurations"

          config = {
            ingress: [
              {
                hostname:,
                service: service_url,
                originRequest: { httpHostHeader: hostname }
              },
              { service: "http_status:404" }
            ]
          }

          put(url, { config: })
        end

        def verify_tunnel_configuration(tunnel_id, expected_hostname, expected_service, max_attempts)
          url = "accounts/#{@account_id}/cfd_tunnel/#{tunnel_id}/configurations"

          max_attempts.times do
            begin
              response = get(url)

              if response["success"]
                config = response.dig("result", "config")
                config&.dig("ingress")&.each do |rule|
                  if rule["hostname"] == expected_hostname && rule["service"] == expected_service
                    return true
                  end
                end
              end
            rescue StandardError
              # Continue retrying
            end

            sleep(2)
          end

          raise Errors::TunnelError, "tunnel configuration not propagated after #{max_attempts} attempts"
        end

        def delete_tunnel(tunnel_id)
          # Clean up all connections first
          connections_url = "accounts/#{@account_id}/cfd_tunnel/#{tunnel_id}/connections"
          begin
            delete(connections_url)
          rescue StandardError
            # Ignore connection cleanup errors
          end

          # Now delete the tunnel
          url = "accounts/#{@account_id}/cfd_tunnel/#{tunnel_id}"
          delete(url)
        end

        # DNS operations

        def find_zone(domain)
          url = "zones"
          response = get(url)

          results = response["result"]
          return nil unless results

          zone_data = results.find { |z| z["name"] == domain }
          return nil unless zone_data

          Objects::Dns::Zone.new(id: zone_data["id"], name: zone_data["name"])
        end

        def find_dns_record(zone_id, name, record_type)
          url = "zones/#{zone_id}/dns_records"
          response = get(url)

          results = response["result"]
          return nil unless results

          record_data = results.find { |r| r["name"] == name && r["type"] == record_type }
          return nil unless record_data

          Objects::Dns::Record.new(
            id: record_data["id"],
            type: record_data["type"],
            name: record_data["name"],
            content: record_data["content"],
            proxied: record_data["proxied"],
            ttl: record_data["ttl"]
          )
        end

        def create_dns_record(zone_id, name, record_type, content, proxied: true)
          url = "zones/#{zone_id}/dns_records"

          response = post(url, {
            type: record_type,
            name:,
            content:,
            proxied:,
            ttl: 1
          })

          result = response["result"]
          Objects::Dns::Record.new(
            id: result["id"],
            type: result["type"],
            name: result["name"],
            content: result["content"],
            proxied: result["proxied"],
            ttl: result["ttl"]
          )
        end

        def update_dns_record(zone_id, record_id, name, record_type, content, proxied: true)
          url = "zones/#{zone_id}/dns_records/#{record_id}"

          response = patch(url, {
            type: record_type,
            name:,
            content:,
            proxied:,
            ttl: 1
          })

          result = response["result"]
          Objects::Dns::Record.new(
            id: result["id"],
            type: result["type"],
            name: result["name"],
            content: result["content"],
            proxied: result["proxied"],
            ttl: result["ttl"]
          )
        end

        def create_or_update_dns_record(zone_id, name, record_type, content, proxied: true)
          existing = find_dns_record(zone_id, name, record_type)

          if existing
            update_dns_record(zone_id, existing.id, name, record_type, content, proxied:)
          else
            create_dns_record(zone_id, name, record_type, content, proxied:)
          end
        end

        def delete_dns_record(zone_id, record_id)
          url = "zones/#{zone_id}/dns_records/#{record_id}"
          delete(url)
        end

        # Validation

        def validate_credentials
          get("user/tokens/verify")
          true
        rescue Errors::CloudflareError => e
          raise Errors::ValidationError, "cloudflare credentials invalid: #{e.message}"
        end

        private

          def get(url, params = {})
            response = @conn.get(url) do |req|
              req.headers["Authorization"] = "Bearer #{@token}"
              req.params = params unless params.empty?
            end
            handle_response(response)
          end

          def post(url, body)
            response = @conn.post(url) do |req|
              req.headers["Authorization"] = "Bearer #{@token}"
              req.body = body
            end
            handle_response(response)
          end

          def put(url, body)
            response = @conn.put(url) do |req|
              req.headers["Authorization"] = "Bearer #{@token}"
              req.body = body
            end
            handle_response(response)
          end

          def patch(url, body)
            response = @conn.patch(url) do |req|
              req.headers["Authorization"] = "Bearer #{@token}"
              req.body = body
            end
            handle_response(response)
          end

          def delete(url)
            response = @conn.delete(url) do |req|
              req.headers["Authorization"] = "Bearer #{@token}"
            end

            # 404 is ok for idempotent delete
            return { "success" => true } if response.status == 404

            handle_response(response)
          end

          def handle_response(response)
            body = response.body

            unless body.is_a?(Hash)
              raise Errors::CloudflareError, "unexpected response format"
            end

            unless body["success"]
              errors = body["errors"]&.map { |e| e["message"] }&.join(", ") || "unknown error"
              raise Errors::CloudflareError, "API error: #{errors}"
            end

            body
          end

          def generate_tunnel_secret
            Base64.strict_encode64(SecureRandom.random_bytes(32))
          end
      end
    end
  end
end
