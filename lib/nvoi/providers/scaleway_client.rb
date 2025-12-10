# frozen_string_literal: true

require "faraday"
require "json"

module Nvoi
  module Providers
    # Raw HTTP client for Scaleway API
    class ScalewayClient
      INSTANCE_API_BASE = "https://api.scaleway.com/instance/v1"
      VPC_API_BASE = "https://api.scaleway.com/vpc/v2"
      BLOCK_API_BASE = "https://api.scaleway.com/block/v1alpha1"

      def initialize(secret_key, project_id, zone: "fr-par-1")
        @secret_key = secret_key
        @project_id = project_id
        @zone = zone
        @region = zone_to_region(zone)
        @conn = build_connection
      end

      attr_reader :zone, :region, :project_id

      # HTTP helpers

      def get(url)
        response = @conn.get(url)
        handle_response(response)
      end

      def post(url, payload = {})
        response = @conn.post(url, payload)
        handle_response(response)
      end

      def patch(url, payload = {})
        response = @conn.patch(url, payload)
        handle_response(response)
      end

      def delete(url)
        response = @conn.delete(url)
        return nil if response.status == 204
        handle_response(response)
      end

      # Server methods

      def list_servers
        get(instance_url("/servers"))["servers"] || []
      end

      def get_server(id)
        get(instance_url("/servers/#{id}"))["server"]
      end

      def create_server(payload)
        post(instance_url("/servers"), payload)["server"]
      end

      def delete_server(id)
        delete(instance_url("/servers/#{id}"))
      end

      def server_action(id, action)
        post(instance_url("/servers/#{id}/action"), { action: })
      end

      def update_server(id, payload)
        patch(instance_url("/servers/#{id}"), payload)["server"]
      end

      # Server type / image methods

      def list_server_types
        get(instance_url("/products/servers"))["servers"] || {}
      end

      def list_images(name: nil, arch: "x86_64")
        params = ["arch=#{arch}"]
        params << "name=#{name}" if name
        get(instance_url("/images?#{params.join("&")}"))["images"] || []
      end

      # Security group methods

      def list_security_groups
        get(instance_url("/security_groups"))["security_groups"] || []
      end

      def get_security_group(id)
        get(instance_url("/security_groups/#{id}"))["security_group"]
      end

      def create_security_group(payload)
        post(instance_url("/security_groups"), payload)["security_group"]
      end

      def delete_security_group(id)
        delete(instance_url("/security_groups/#{id}"))
      end

      def create_security_group_rule(security_group_id, payload)
        post(instance_url("/security_groups/#{security_group_id}/rules"), payload)["rule"]
      end

      # Private network methods (regional - VPC API)

      def list_private_networks
        get(vpc_url("/private-networks"))["private_networks"] || []
      end

      def get_private_network(id)
        get(vpc_url("/private-networks/#{id}"))
      end

      def create_private_network(payload)
        post(vpc_url("/private-networks"), payload)
      end

      def delete_private_network(id)
        delete(vpc_url("/private-networks/#{id}"))
      end

      # Private NIC methods (zoned - Instance API)

      def list_private_nics(server_id)
        get(instance_url("/servers/#{server_id}/private_nics"))["private_nics"] || []
      end

      def create_private_nic(server_id, private_network_id)
        post(instance_url("/servers/#{server_id}/private_nics"), { private_network_id: })["private_nic"]
      end

      def delete_private_nic(server_id, nic_id)
        delete(instance_url("/servers/#{server_id}/private_nics/#{nic_id}"))
      end

      # Volume methods (zoned - Block API)

      def list_volumes
        get(block_url("/volumes"))["volumes"] || []
      end

      def get_volume(id)
        get(block_url("/volumes/#{id}"))
      end

      def create_volume(payload)
        post(block_url("/volumes"), payload)
      end

      def delete_volume(id)
        delete(block_url("/volumes/#{id}"))
      end

      # User data methods

      def set_user_data(server_id, key, content)
        url = instance_url("/servers/#{server_id}/user_data/#{key}")
        response = @conn.patch(url) do |req|
          req.headers["Content-Type"] = "text/plain"
          req.body = content
        end
        handle_response(response)
      end

      private

        def zone_to_region(zone)
          zone.split("-")[0..1].join("-")
        end

        def instance_url(path)
          "#{INSTANCE_API_BASE}/zones/#{@zone}#{path}"
        end

        def vpc_url(path)
          "#{VPC_API_BASE}/regions/#{@region}#{path}"
        end

        def block_url(path)
          "#{BLOCK_API_BASE}/zones/#{@zone}#{path}"
        end

        def build_connection
          Faraday.new do |f|
            f.request :json
            f.response :json
            f.headers["X-Auth-Token"] = @secret_key
            f.headers["Content-Type"] = "application/json"
          end
        end

        def handle_response(response)
          case response.status
          when 200..299
            response.body
          when 401
            raise AuthenticationError, "Invalid Scaleway API token"
          when 403
            raise AuthenticationError, "Forbidden: check project_id and permissions"
          when 404
            raise NotFoundError, parse_error(response)
          when 409
            raise ConflictError, parse_error(response)
          when 422
            raise ValidationError, parse_error(response)
          when 429
            raise RateLimitError, "Rate limited, retry later"
          else
            raise APIError, parse_error(response)
          end
        end

        def parse_error(response)
          if response.body.is_a?(Hash)
            response.body["message"] || response.body.to_s
          else
            "HTTP #{response.status}: #{response.body}"
          end
        end
    end
  end
end
