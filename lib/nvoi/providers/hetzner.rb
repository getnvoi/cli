# frozen_string_literal: true

require_relative "hetzner_client"

module Nvoi
  module Providers
    # Hetzner provider implements the compute provider interface for Hetzner Cloud
    class Hetzner < Base
      def initialize(token)
        @client = HetznerClient.new(token)
      end

      # Network operations

      def find_or_create_network(name)
        network = find_network_by_name(name)
        return to_network(network) if network

        network = @client.create_network(
          name: name,
          ip_range: Constants::NETWORK_CIDR,
          subnets: [{
            type: "cloud",
            ip_range: Constants::SUBNET_CIDR,
            network_zone: "eu-central"
          }]
        )

        to_network(network)
      end

      def get_network_by_name(name)
        network = find_network_by_name(name)
        raise NetworkError, "network not found: #{name}" unless network

        to_network(network)
      end

      def delete_network(id)
        @client.delete_network(id.to_i)
      end

      # Firewall operations

      def find_or_create_firewall(name)
        firewall = find_firewall_by_name(name)
        return to_firewall(firewall) if firewall

        firewall = @client.create_firewall(
          name: name,
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
        raise FirewallError, "firewall not found: #{name}" unless firewall

        to_firewall(firewall)
      end

      def delete_firewall(id)
        @client.delete_firewall(id.to_i)
      end

      # Server operations

      def find_server(name)
        server = find_server_by_name(name)
        return nil unless server

        to_server(server)
      end

      def list_servers
        @client.list_servers.map { |s| to_server(s) }
      end

      def create_server(opts)
        # Resolve IDs
        server_type = find_server_type(opts.type)
        raise ValidationError, "invalid server type: #{opts.type}" unless server_type

        image = find_image(opts.image)
        raise ValidationError, "invalid image: #{opts.image}" unless image

        location = find_location(opts.location)
        raise ValidationError, "invalid location: #{opts.location}" unless location

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

        server = @client.create_server(create_opts)
        to_server(server)
      end

      def wait_for_server(server_id, max_attempts)
        max_attempts.times do
          server = @client.get_server(server_id.to_i)

          if server["status"] == "running"
            return to_server(server)
          end

          sleep(Constants::SERVER_READY_INTERVAL)
        end

        raise ServerCreationError, "server did not become running after #{max_attempts} attempts"
      end

      def delete_server(id)
        server = @client.get_server(id.to_i)

        # Remove from firewalls
        @client.list_firewalls.each do |fw|
          fw["applied_to"]&.each do |applied|
            next unless applied["type"] == "server" && applied.dig("server", "id") == id.to_i

            @client.remove_firewall_from_server(fw["id"], id.to_i)
          rescue StandardError
            # Ignore cleanup errors
          end
        end

        # Detach from networks
        server["private_net"]&.each do |pn|
          @client.detach_server_from_network(id.to_i, pn["network"])
        rescue StandardError
          # Ignore cleanup errors
        end

        @client.delete_server(id.to_i)
      end

      # Volume operations

      def create_volume(opts)
        server = @client.get_server(opts.server_id.to_i)
        raise VolumeError, "server not found: #{opts.server_id}" unless server

        volume = @client.create_volume(
          name: opts.name,
          size: opts.size,
          location: server.dig("datacenter", "location", "name"),
          format: "xfs"
        )

        to_volume(volume)
      end

      def get_volume(id)
        volume = @client.get_volume(id.to_i)
        return nil unless volume

        to_volume(volume)
      end

      def get_volume_by_name(name)
        volume = @client.list_volumes.find { |v| v["name"] == name }
        return nil unless volume

        to_volume(volume)
      end

      def delete_volume(id)
        @client.delete_volume(id.to_i)
      end

      def attach_volume(volume_id, server_id)
        @client.attach_volume(volume_id.to_i, server_id.to_i)
      end

      def detach_volume(volume_id)
        @client.detach_volume(volume_id.to_i)
      end

      # Validation operations

      def validate_instance_type(instance_type)
        server_type = find_server_type(instance_type)
        raise ValidationError, "invalid hetzner server type: #{instance_type}" unless server_type

        true
      end

      def validate_region(region)
        location = find_location(region)
        raise ValidationError, "invalid hetzner location: #{region}" unless location

        true
      end

      def validate_credentials
        @client.list_server_types
        true
      rescue AuthenticationError => e
        raise ValidationError, "hetzner credentials invalid: #{e.message}"
      end

      private

      def find_network_by_name(name)
        @client.list_networks.find { |n| n["name"] == name }
      end

      def find_firewall_by_name(name)
        @client.list_firewalls.find { |f| f["name"] == name }
      end

      def find_server_by_name(name)
        @client.list_servers.find { |s| s["name"] == name }
      end

      def find_server_type(name)
        @client.list_server_types.find { |t| t["name"] == name }
      end

      def find_image(name)
        # Images endpoint requires filtering
        response = @client.get("/images?name=#{name}")
        response["images"]&.first
      end

      def find_location(name)
        @client.list_locations.find { |l| l["name"] == name }
      end

      def to_network(data)
        Network.new(
          id: data["id"].to_s,
          name: data["name"],
          ip_range: data["ip_range"]
        )
      end

      def to_firewall(data)
        Firewall.new(
          id: data["id"].to_s,
          name: data["name"]
        )
      end

      def to_server(data)
        Server.new(
          id: data["id"].to_s,
          name: data["name"],
          status: data["status"],
          public_ipv4: data.dig("public_net", "ipv4", "ip")
        )
      end

      def to_volume(data)
        Volume.new(
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
