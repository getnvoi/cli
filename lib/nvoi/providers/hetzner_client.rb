# frozen_string_literal: true

require "faraday"
require "json"

module Nvoi
  module Providers
    # Raw HTTP client for Hetzner Cloud API
    class HetznerClient
      BASE_URL = "https://api.hetzner.cloud/v1"

      def initialize(token)
        @token = token
        @conn = Faraday.new do |f|
          f.request :json
          f.response :json
          f.headers["Authorization"] = "Bearer #{token}"
        end
      end

      def get(path)
        response = @conn.get("#{BASE_URL}#{path}")
        handle_response(response)
      end

      def post(path, payload = {})
        response = @conn.post("#{BASE_URL}#{path}", payload)
        handle_response(response)
      end

      def delete(path)
        response = @conn.delete("#{BASE_URL}#{path}")
        return nil if response.status == 204
        handle_response(response)
      end

      # Server types
      def list_server_types
        get("/server_types")["server_types"]
      end

      # Locations
      def list_locations
        get("/locations")["locations"]
      end

      # Servers
      def list_servers
        get("/servers")["servers"]
      end

      def get_server(id)
        get("/servers/#{id}")["server"]
      end

      def create_server(payload)
        post("/servers", payload)["server"]
      end

      def delete_server(id)
        delete("/servers/#{id}")
      end

      # Networks
      def list_networks
        get("/networks")["networks"]
      end

      def create_network(payload)
        post("/networks", payload)["network"]
      end

      def delete_network(id)
        delete("/networks/#{id}")
      end

      # Firewalls
      def list_firewalls
        get("/firewalls")["firewalls"]
      end

      def create_firewall(payload)
        post("/firewalls", payload)["firewall"]
      end

      def delete_firewall(id)
        delete("/firewalls/#{id}")
      end

      def apply_firewall_to_server(firewall_id, server_id)
        payload = {
          apply_to: [{
            type: "server",
            server: { id: server_id }
          }]
        }
        post("/firewalls/#{firewall_id}/actions/apply_to_resources", payload)
      end

      def remove_firewall_from_server(firewall_id, server_id)
        payload = {
          remove_from: [{
            type: "server",
            server: { id: server_id }
          }]
        }
        post("/firewalls/#{firewall_id}/actions/remove_from_resources", payload)
      end

      # Volumes
      def list_volumes
        get("/volumes")["volumes"]
      end

      def get_volume(id)
        get("/volumes/#{id}")["volume"]
      end

      def create_volume(payload)
        post("/volumes", payload)["volume"]
      end

      def delete_volume(id)
        delete("/volumes/#{id}")
      end

      def attach_volume(volume_id, server_id)
        post("/volumes/#{volume_id}/actions/attach", { server: server_id })
      end

      def detach_volume(volume_id)
        post("/volumes/#{volume_id}/actions/detach", {})
      end

      # Server network attachment
      def attach_server_to_network(server_id, network_id)
        post("/servers/#{server_id}/actions/attach_to_network", { network: network_id })
      end

      def detach_server_from_network(server_id, network_id)
        post("/servers/#{server_id}/actions/detach_from_network", { network: network_id })
      end

      private

        def handle_response(response)
          case response.status
          when 200..299
            response.body
          when 401
            raise AuthenticationError, "Invalid Hetzner API token"
          when 404
            raise NotFoundError, parse_error(response)
          when 422
            raise ValidationError, parse_error(response)
          else
            raise APIError, parse_error(response)
          end
        end

        def parse_error(response)
          if response.body.is_a?(Hash) && response.body["error"]
            response.body["error"]["message"]
          else
            "HTTP #{response.status}: #{response.body}"
          end
        end
    end
  end
end
