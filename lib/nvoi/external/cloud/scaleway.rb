# frozen_string_literal: true

require "faraday"
require "json"

module Nvoi
  module External
    module Cloud
      # Scaleway provider implements the compute provider interface for Scaleway Cloud
      class Scaleway < Base
        INSTANCE_API_BASE = "https://api.scaleway.com/instance/v1"
        VPC_API_BASE = "https://api.scaleway.com/vpc/v2"
        BLOCK_API_BASE = "https://api.scaleway.com/block/v1alpha1"

        VALID_ZONES = %w[
          fr-par-1 fr-par-2 fr-par-3
          nl-ams-1 nl-ams-2 nl-ams-3
          pl-waw-1 pl-waw-2 pl-waw-3
        ].freeze

        def initialize(secret_key, project_id, zone: "fr-par-1")
          @secret_key = secret_key
          @project_id = project_id
          @zone = zone
          @region = zone_to_region(zone)
          @conn = build_connection
        end

        attr_reader :zone, :region, :project_id

        # Network operations

        def find_or_create_network(name)
          network = find_network_by_name(name)
          return to_network(network) if network

          network = post(vpc_url("/private-networks"), {
            name:,
            project_id: @project_id
          })

          to_network(network)
        end

        def get_network_by_name(name)
          network = find_network_by_name(name)
          raise Errors::NetworkError, "network not found: #{name}" unless network

          to_network(network)
        end

        def delete_network(id)
          # First detach all servers from this network
          list_servers_api.each do |server|
            nics = list_private_nics(server["id"])
            nics.each do |nic|
              next unless nic["private_network_id"] == id

              delete_private_nic(server["id"], nic["id"])
            rescue StandardError
              # Ignore cleanup errors
            end
          end

          delete(vpc_url("/private-networks/#{id}"))
        end

        # Firewall operations (Security Groups)

        def find_or_create_firewall(name)
          sg = find_security_group_by_name(name)
          return to_firewall(sg) if sg

          sg = post(instance_url("/security_groups"), {
            name:,
            project: @project_id,
            stateful: true,
            inbound_default_policy: "drop",
            outbound_default_policy: "accept"
          })["security_group"]

          # Add SSH rule
          post(instance_url("/security_groups/#{sg["id"]}/rules"), {
            protocol: "TCP",
            direction: "inbound",
            action: "accept",
            ip_range: "0.0.0.0/0",
            dest_port_from: 22,
            dest_port_to: 22
          })

          to_firewall(sg)
        end

        def get_firewall_by_name(name)
          sg = find_security_group_by_name(name)
          raise Errors::FirewallError, "security group not found: #{name}" unless sg

          to_firewall(sg)
        end

        def delete_firewall(id)
          delete(instance_url("/security_groups/#{id}"))
        end

        # Server operations

        def find_server(name)
          server = find_server_by_name(name)
          return nil unless server

          to_server(server)
        end

        def find_server_by_id(id)
          server = get(instance_url("/servers/#{id}"))["server"]
          return nil unless server

          to_server(server)
        rescue Errors::NotFoundError
          nil
        end

        def list_servers
          list_servers_api.map { |s| to_server(s) }
        end

        def create_server(opts)
          # Validate server type
          server_types = list_server_types
          unless server_types.key?(opts.type)
            raise Errors::ValidationError, "invalid server type: #{opts.type}"
          end

          # Resolve image
          image = find_image(opts.image)
          raise Errors::ValidationError, "invalid image: #{opts.image}" unless image

          create_opts = {
            name: opts.name,
            commercial_type: opts.type,
            image: image["id"],
            project: @project_id,
            boot_type: "local",
            tags: []
          }

          # Add security group if provided
          if opts.firewall_id && !opts.firewall_id.empty?
            create_opts[:security_group] = opts.firewall_id
          end

          server = post(instance_url("/servers"), create_opts)["server"]

          # Set cloud-init user data if provided
          if opts.user_data && !opts.user_data.empty?
            set_user_data(server["id"], "cloud-init", opts.user_data)
          end

          # Power on the server
          server_action(server["id"], "poweron")

          # Attach to private network if provided
          if opts.network_id && !opts.network_id.empty?
            wait_for_server_state(server["id"], "running", 30)
            create_private_nic(server["id"], opts.network_id)
          end

          to_server(get_server_api(server["id"]))
        end

        def wait_for_server(server_id, max_attempts)
          server = Utils::Retry.poll(max_attempts: max_attempts, interval: Utils::Constants::SERVER_READY_INTERVAL) do
            s = get_server_api(server_id)
            to_server(s) if s["state"] == "running" && s.dig("public_ip", "address")
          end

          raise Errors::ServerCreationError, "server did not become running after #{max_attempts} attempts" unless server

          server
        end

        def delete_server(id)
          # Delete private NICs first
          nics = list_private_nics(id)
          nics.each do |nic|
            delete_private_nic(id, nic["id"])
          rescue StandardError
            # Ignore cleanup errors
          end

          # Terminate server (this also stops and deletes)
          server_action(id, "terminate")
        rescue StandardError => e
          # If terminate fails, try poweroff then delete
          begin
            server_action(id, "poweroff")
            sleep(5)
            delete(instance_url("/servers/#{id}"))
          rescue StandardError
            raise e
          end
        end

        # Volume operations

        def create_volume(opts)
          server = get_server_api(opts.server_id)
          raise Errors::VolumeError, "server not found: #{opts.server_id}" unless server

          volume = post(block_url("/volumes"), {
            name: opts.name,
            perf_iops: 5000,
            from_empty: { size: opts.size * 1_000_000_000 },
            project_id: @project_id
          })

          to_volume(volume)
        end

        def get_volume(id)
          volume = get(block_url("/volumes/#{id}"))
          return nil unless volume

          to_volume(volume)
        rescue Errors::NotFoundError
          nil
        end

        def get_volume_by_name(name)
          volume = list_volumes.find { |v| v["name"] == name }
          return nil unless volume

          to_volume(volume)
        end

        def delete_volume(id)
          delete(block_url("/volumes/#{id}"))
        end

        def attach_volume(volume_id, server_id)
          server = get_server_api(server_id)
          raise Errors::VolumeError, "server not found: #{server_id}" unless server

          wait_for_volume_available(volume_id)

          current_volumes = server["volumes"] || {}
          next_index = current_volumes.keys.map(&:to_i).max.to_i + 1

          new_volumes = current_volumes.dup
          new_volumes[next_index.to_s] = { id: volume_id, volume_type: "sbs_volume" }

          patch(instance_url("/servers/#{server_id}"), { volumes: new_volumes })
        end

        def detach_volume(volume_id)
          list_servers_api.each do |server|
            volumes = server["volumes"] || {}
            volumes.each do |idx, vol|
              next unless vol["id"] == volume_id

              new_volumes = volumes.reject { |k, _| k == idx }
              patch(instance_url("/servers/#{server["id"]}"), { volumes: new_volumes })
              return
            end
          end
        end

        def wait_for_device_path(volume_id, ssh)
          # Scaleway doesn't provide device_path in API
          # Find device by volume ID in /dev/disk/by-id/
          Utils::Retry.poll(max_attempts: 30, interval: 2) do
            output = ssh.execute("ls /dev/disk/by-id/ 2>/dev/null | grep -i '#{volume_id}' || true").strip
            next nil if output.empty?

            device_name = output.lines.first.strip
            "/dev/disk/by-id/#{device_name}"
          end
        end

        # Validation operations

        def validate_instance_type(instance_type)
          server_types = list_server_types
          unless server_types.key?(instance_type)
            raise Errors::ValidationError, "invalid scaleway server type: #{instance_type}"
          end

          true
        end

        def validate_region(region)
          unless VALID_ZONES.include?(region)
            raise Errors::ValidationError, "invalid scaleway zone: #{region}. Valid: #{VALID_ZONES.join(", ")}"
          end

          true
        end

        def validate_credentials
          list_server_types
          true
        rescue Errors::AuthenticationError => e
          raise Errors::ValidationError, "scaleway credentials invalid: #{e.message}"
        end

        # Server IP lookup for exec/db commands
        def server_ip(server_name)
          server = find_server(server_name)
          server&.public_ipv4
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

          def get(url)
            response = @conn.get(url)
            handle_response(response)
          end

          def post(url, payload = {})
            response = @conn.post(url, payload)
            handle_response(response, url, payload)
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

          def handle_response(response, url = nil, payload = nil)
            case response.status
            when 200..299
              response.body
            when 401
              raise Errors::AuthenticationError, "Invalid Scaleway API token"
            when 403
              raise Errors::AuthenticationError, "Forbidden: check project_id and permissions"
            when 404
              raise Errors::NotFoundError, parse_error(response)
            when 409
              raise Errors::ConflictError, parse_error(response)
            when 422
              raise Errors::ValidationError, parse_error(response)
            when 429
              raise Errors::RateLimitError, "Rate limited, retry later"
            else
              debug = "HTTP #{response.status}: #{parse_error(response)}"
              debug += "\nURL: #{url}" if url
              debug += "\nPayload: #{payload.inspect}" if payload
              raise Errors::ApiError, debug
            end
          end

          def parse_error(response)
            if response.body.is_a?(Hash)
              response.body["message"] || response.body.inspect
            else
              response.body.to_s
            end
          end

          def list_servers_api
            get(instance_url("/servers"))["servers"] || []
          end

          def get_server_api(id)
            get(instance_url("/servers/#{id}"))["server"]
          end

          def server_action(id, action)
            post(instance_url("/servers/#{id}/action"), { action: })
          end

          def list_server_types
            get(instance_url("/products/servers"))["servers"] || {}
          end

          def list_images(name: nil, arch: "x86_64")
            params = ["arch=#{arch}"]
            params << "name=#{name}" if name
            get(instance_url("/images?#{params.join("&")}"))["images"] || []
          end

          def list_volumes
            get(block_url("/volumes"))["volumes"] || []
          end

          def list_private_nics(server_id)
            get(instance_url("/servers/#{server_id}/private_nics"))["private_nics"] || []
          end

          def create_private_nic(server_id, private_network_id)
            post(instance_url("/servers/#{server_id}/private_nics"), { private_network_id: })["private_nic"]
          end

          def delete_private_nic(server_id, nic_id)
            delete(instance_url("/servers/#{server_id}/private_nics/#{nic_id}"))
          end

          def set_user_data(server_id, key, content)
            url = instance_url("/servers/#{server_id}/user_data/#{key}")
            response = @conn.patch(url) do |req|
              req.headers["Content-Type"] = "text/plain"
              req.body = content
            end
            handle_response(response)
          end

          def wait_for_volume_available(volume_id, timeout: 60)
            deadline = Time.now + timeout
            loop do
              vol = get(block_url("/volumes/#{volume_id}"))
              return if vol && vol["status"] == "available"

              raise Errors::VolumeError, "volume #{volume_id} did not become available" if Time.now > deadline

              sleep 2
            end
          end

          def wait_for_server_state(server_id, target_state, max_attempts)
            Utils::Retry.poll(max_attempts: max_attempts, interval: 2) do
              server = get_server_api(server_id)
              server if server["state"] == target_state
            end
          end

          def find_network_by_name(name)
            networks = get(vpc_url("/private-networks"))["private_networks"] || []
            networks.find { |n| n["name"] == name }
          end

          def find_security_group_by_name(name)
            sgs = get(instance_url("/security_groups"))["security_groups"] || []
            sgs.find { |sg| sg["name"] == name }
          end

          def find_server_by_name(name)
            list_servers_api.find { |s| s["name"] == name }
          end

          def find_image(name)
            image_name = case name
            when "ubuntu-24.04" then "ubuntu_noble"
            when "ubuntu-22.04" then "ubuntu_jammy"
            when "ubuntu-20.04" then "ubuntu_focal"
            when "debian-12" then "debian_bookworm"
            when "debian-11" then "debian_bullseye"
            else name
            end

            images = list_images(name: image_name)
            images&.first
          end

          def to_network(data)
            Objects::Network::Record.new(
              id: data["id"],
              name: data["name"],
              ip_range: data.dig("subnets", 0, "subnet") || data["subnets"]&.first
            )
          end

          def to_firewall(data)
            Objects::Firewall::Record.new(
              id: data["id"],
              name: data["name"]
            )
          end

          def to_server(data)
            Objects::Server::Record.new(
              id: data["id"],
              name: data["name"],
              status: data["state"],
              public_ipv4: data.dig("public_ip", "address")
            )
          end

          def to_volume(data)
            server_id = data["references"]&.find { |r|
              r["product_resource_type"] == "instance_server"
            }&.dig("product_resource_id")

            Objects::Volume::Record.new(
              id: data["id"],
              name: data["name"],
              size: (data["size"] || 0) / 1_000_000_000,
              location: data["zone"],
              status: data["status"],
              server_id:,
              device_path: nil
            )
          end
      end
    end
  end
end
