# frozen_string_literal: true

require "faraday"
require "json"

module Nvoi
  module External
    module Cloud
      # Hetzner provider implements the compute provider interface for Hetzner Cloud
      class Hetzner < Base
        BASE_URL = "https://api.hetzner.cloud/v1"

        def initialize(token)
          @token = token
          @conn = Faraday.new do |f|
            f.request :json
            f.response :json
            f.headers["Authorization"] = "Bearer #{token}"
          end
        end

        # Network operations

        def find_or_create_network(name)
          network = find_network_by_name(name)
          return to_network(network) if network

          network = create_network_api(
            name:,
            ip_range: Utils::Constants::NETWORK_CIDR,
            subnets: [{
              type: "cloud",
              ip_range: Utils::Constants::SUBNET_CIDR,
              network_zone: "eu-central"
            }]
          )

          to_network(network)
        end

        def get_network_by_name(name)
          network = find_network_by_name(name)
          raise Errors::NetworkError, "network not found: #{name}" unless network

          to_network(network)
        end

        def delete_network(id)
          delete("/networks/#{id.to_i}")
        end

        # Firewall operations

        def find_or_create_firewall(name)
          firewall = find_firewall_by_name(name)
          return to_firewall(firewall) if firewall

          firewall = create_firewall_api(
            name:,
            rules: [{
              direction: "in",
              protocol: "tcp",
              port: "22",
              source_ips: ["0.0.0.0/0", "::/0"]
            }]
          )

          to_firewall(firewall)
        end

        def get_firewall_by_name(name)
          firewall = find_firewall_by_name(name)
          raise Errors::FirewallError, "firewall not found: #{name}" unless firewall

          to_firewall(firewall)
        end

        def delete_firewall(id)
          delete("/firewalls/#{id.to_i}")
        end

        # Server operations

        def find_server(name)
          server = find_server_by_name(name)
          return nil unless server

          to_server(server)
        end

        def find_server_by_id(id)
          server = get("/servers/#{id.to_i}")["server"]
          return nil unless server

          to_server(server)
        rescue Errors::NotFoundError
          nil
        end

        def list_servers
          get("/servers")["servers"].map { |s| to_server(s) }
        end

        def create_server(opts)
          # Resolve IDs
          server_type = find_server_type(opts.type)
          raise Errors::ValidationError, "invalid server type: #{opts.type}" unless server_type

          image = find_image(opts.image)
          raise Errors::ValidationError, "invalid image: #{opts.image}" unless image

          location = find_location(opts.location)
          raise Errors::ValidationError, "invalid location: #{opts.location}" unless location

          create_opts = {
            name: opts.name,
            server_type: server_type["name"],
            image: image["name"],
            location: location["name"],
            user_data: opts.user_data,
            start_after_create: true
          }

          # Add network if provided
          if opts.network_id && !opts.network_id.empty?
            create_opts[:networks] = [opts.network_id.to_i]
          end

          # Add firewall if provided
          if opts.firewall_id && !opts.firewall_id.empty?
            create_opts[:firewalls] = [{ firewall: opts.firewall_id.to_i }]
          end

          server = post("/servers", create_opts)["server"]
          to_server(server)
        end

        def wait_for_server(server_id, max_attempts)
          server = Utils::Retry.poll(max_attempts: max_attempts, interval: Utils::Constants::SERVER_READY_INTERVAL) do
            s = get("/servers/#{server_id.to_i}")["server"]
            to_server(s) if s["status"] == "running"
          end

          raise Errors::ServerCreationError, "server did not become running after #{max_attempts} attempts" unless server

          server
        end

        def delete_server(id)
          server = get("/servers/#{id.to_i}")["server"]

          # Remove from firewalls
          get("/firewalls")["firewalls"].each do |fw|
            fw["applied_to"]&.each do |applied|
              next unless applied["type"] == "server" && applied.dig("server", "id") == id.to_i

              remove_firewall_from_server(fw["id"], id.to_i)
            rescue StandardError
              # Ignore cleanup errors
            end
          end

          # Detach from networks
          server["private_net"]&.each do |pn|
            detach_server_from_network(id.to_i, pn["network"])
          rescue StandardError
            # Ignore cleanup errors
          end

          delete("/servers/#{id.to_i}")
        end

        # Volume operations

        def create_volume(opts)
          server = get("/servers/#{opts.server_id.to_i}")["server"]
          raise Errors::VolumeError, "server not found: #{opts.server_id}" unless server

          volume = post("/volumes", {
            name: opts.name,
            size: opts.size,
            location: server.dig("datacenter", "location", "name"),
            format: "xfs"
          })["volume"]

          to_volume(volume)
        end

        def get_volume(id)
          volume = get("/volumes/#{id.to_i}")["volume"]
          return nil unless volume

          to_volume(volume)
        end

        def get_volume_by_name(name)
          volume = get("/volumes")["volumes"].find { |v| v["name"] == name }
          return nil unless volume

          to_volume(volume)
        end

        def delete_volume(id)
          delete("/volumes/#{id.to_i}")
        end

        def attach_volume(volume_id, server_id)
          post("/volumes/#{volume_id.to_i}/actions/attach", { server: server_id.to_i })
        end

        def detach_volume(volume_id)
          post("/volumes/#{volume_id.to_i}/actions/detach", {})
        end

        def wait_for_device_path(volume_id, _ssh)
          # Hetzner provides device_path in API response
          Utils::Retry.poll(max_attempts: 30, interval: 2) do
            volume = get("/volumes/#{volume_id.to_i}")["volume"]
            volume["linux_device"] if volume && volume["linux_device"] && !volume["linux_device"].empty?
          end
        end

        # Validation operations

        def validate_instance_type(instance_type)
          server_type = find_server_type(instance_type)
          raise Errors::ValidationError, "invalid hetzner server type: #{instance_type}" unless server_type

          true
        end

        def validate_region(region)
          location = find_location(region)
          raise Errors::ValidationError, "invalid hetzner location: #{region}" unless location

          true
        end

        def validate_credentials
          get("/server_types")
          true
        rescue Errors::AuthenticationError => e
          raise Errors::ValidationError, "hetzner credentials invalid: #{e.message}"
        end

        private

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

          def handle_response(response)
            case response.status
            when 200..299
              response.body
            when 401
              raise Errors::AuthenticationError, "Invalid Hetzner API token"
            when 404
              raise Errors::NotFoundError, parse_error(response)
            when 422
              raise Errors::ValidationError, parse_error(response)
            else
              raise Errors::ApiError, parse_error(response)
            end
          end

          def parse_error(response)
            if response.body.is_a?(Hash) && response.body["error"]
              response.body["error"]["message"]
            else
              "HTTP #{response.status}: #{response.body}"
            end
          end

          def find_network_by_name(name)
            get("/networks")["networks"].find { |n| n["name"] == name }
          end

          def find_firewall_by_name(name)
            get("/firewalls")["firewalls"].find { |f| f["name"] == name }
          end

          def find_server_by_name(name)
            get("/servers")["servers"].find { |s| s["name"] == name }
          end

          def find_server_type(name)
            get("/server_types")["server_types"].find { |t| t["name"] == name }
          end

          def find_image(name)
            response = get("/images?name=#{name}")
            response["images"]&.first
          end

          def find_location(name)
            get("/locations")["locations"].find { |l| l["name"] == name }
          end

          def create_network_api(payload)
            post("/networks", payload)["network"]
          end

          def create_firewall_api(payload)
            post("/firewalls", payload)["firewall"]
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

          def detach_server_from_network(server_id, network_id)
            post("/servers/#{server_id}/actions/detach_from_network", { network: network_id })
          end

          def to_network(data)
            Objects::Network::Record.new(
              id: data["id"].to_s,
              name: data["name"],
              ip_range: data["ip_range"]
            )
          end

          def to_firewall(data)
            Objects::Firewall::Record.new(
              id: data["id"].to_s,
              name: data["name"]
            )
          end

          def to_server(data)
            Objects::Server::Record.new(
              id: data["id"].to_s,
              name: data["name"],
              status: data["status"],
              public_ipv4: data.dig("public_net", "ipv4", "ip")
            )
          end

          def to_volume(data)
            Objects::Volume::Record.new(
              id: data["id"].to_s,
              name: data["name"],
              size: data["size"],
              location: data.dig("location", "name"),
              status: data["status"],
              server_id: data["server"]&.to_s,
              device_path: data["linux_device"]
            )
          end
      end
    end
  end
end
