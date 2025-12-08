# frozen_string_literal: true

require "hcloud"

module Nvoi
  module Providers
    # Hetzner provider implements the compute provider interface for Hetzner Cloud
    class Hetzner < Base
      def initialize(token)
        @client = Hcloud::Client.new(token: token)
      end

      # Network operations

      def find_or_create_network(name)
        # Try to find existing network
        network = @client.networks.to_a.find { |n| n.name == name }

        if network
          return Network.new(
            id: network.id.to_s,
            name: network.name,
            ip_range: network.ip_range
          )
        end

        # Create new network
        network = @client.networks.create(
          name: name,
          ip_range: Constants::NETWORK_CIDR,
          subnets: [{
            type: "cloud",
            ip_range: Constants::SUBNET_CIDR,
            network_zone: "eu-central"
          }]
        )

        Network.new(
          id: network.id.to_s,
          name: network.name,
          ip_range: network.ip_range
        )
      end

      def get_network_by_name(name)
        network = @client.networks.to_a.find { |n| n.name == name }
        raise NetworkError, "network not found: #{name}" unless network

        Network.new(
          id: network.id.to_s,
          name: network.name,
          ip_range: network.ip_range
        )
      end

      def delete_network(id)
        @client.networks.find(id.to_i).destroy
      end

      # Firewall operations

      def find_or_create_firewall(name)
        # Try to find existing firewall
        firewall = @client.firewalls.to_a.find { |f| f.name == name }

        if firewall
          return Firewall.new(
            id: firewall.id.to_s,
            name: firewall.name
          )
        end

        # Create new firewall with SSH access
        firewall = @client.firewalls.create(
          name: name,
          rules: [{
            direction: "in",
            protocol: "tcp",
            port: "22",
            source_ips: ["0.0.0.0/0", "::/0"]
          }]
        )

        Firewall.new(
          id: firewall.id.to_s,
          name: firewall.name
        )
      end

      def get_firewall_by_name(name)
        firewall = @client.firewalls.to_a.find { |f| f.name == name }
        raise FirewallError, "firewall not found: #{name}" unless firewall

        Firewall.new(
          id: firewall.id.to_s,
          name: firewall.name
        )
      end

      def delete_firewall(id)
        @client.firewalls.find(id.to_i).destroy
      end

      # Server operations

      def find_server(name)
        server = @client.servers.to_a.find { |s| s.name == name }
        return nil unless server

        Server.new(
          id: server.id.to_s,
          name: server.name,
          status: server.status,
          public_ipv4: server.public_net&.ipv4&.ip
        )
      end

      def list_servers
        @client.servers.map do |server|
          Server.new(
            id: server.id.to_s,
            name: server.name,
            status: server.status,
            public_ipv4: server.public_net&.ipv4&.ip
          )
        end
      end

      def create_server(opts)
        server_type = @client.server_types.to_a.find { |t| t.name == opts.type }
        raise ValidationError, "invalid server type: #{opts.type}" unless server_type

        image = @client.images.to_a.find { |i| i.name == opts.image }
        raise ValidationError, "invalid image: #{opts.image}" unless image

        location = @client.locations.to_a.find { |l| l.name == opts.location }
        raise ValidationError, "invalid location: #{opts.location}" unless location

        create_opts = {
          name: opts.name,
          server_type: server_type.id,
          image: image.id,
          location: location.id,
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

        result = @client.servers.create(**create_opts)
        server = result.is_a?(Hash) ? result[:server] : result

        Server.new(
          id: server.id.to_s,
          name: server.name,
          status: server.status,
          public_ipv4: server.public_net&.ipv4&.ip
        )
      end

      def wait_for_server(server_id, max_attempts)
        max_attempts.times do |i|
          server = @client.servers.find(server_id.to_i)

          if server.status == "running"
            return Server.new(
              id: server.id.to_s,
              name: server.name,
              status: server.status,
              public_ipv4: server.public_net&.ipv4&.ip
            )
          end

          sleep(Constants::SERVER_READY_INTERVAL)
        end

        raise ServerCreationError, "server did not become running after #{max_attempts} attempts"
      end

      def delete_server(id)
        server = @client.servers.find(id.to_i)

        # Remove from firewalls
        @client.firewalls.each do |fw|
          fw.applied_to&.each do |applied|
            next unless applied[:type] == "server" && applied.dig(:server, :id) == id.to_i

            fw.remove_target(type: "server", server: { id: id.to_i })
          rescue StandardError
            # Ignore cleanup errors
          end
        end

        # Detach from networks
        server.private_net&.each do |pn|
          server.detach_from_network(network: pn[:network][:id])
        rescue StandardError
          # Ignore cleanup errors
        end

        server.destroy
      end

      # Volume operations

      def create_volume(opts)
        server = @client.servers.find(opts.server_id.to_i)
        raise VolumeError, "server not found: #{opts.server_id}" unless server

        volume = @client.volumes.create(
          name: opts.name,
          size: opts.size,
          location: server.datacenter.location.name,
          format: "xfs"
        )

        Volume.new(
          id: volume.id.to_s,
          name: volume.name,
          size: volume.size,
          location: volume.location.name,
          status: volume.status
        )
      end

      def get_volume(id)
        volume = @client.volumes.find(id.to_i)
        return nil unless volume

        Volume.new(
          id: volume.id.to_s,
          name: volume.name,
          size: volume.size,
          location: volume.location.name,
          status: volume.status,
          server_id: volume.server&.id&.to_s,
          device_path: volume.linux_device
        )
      end

      def get_volume_by_name(name)
        volume = @client.volumes.to_a.find { |v| v.name == name }
        return nil unless volume

        Volume.new(
          id: volume.id.to_s,
          name: volume.name,
          size: volume.size,
          location: volume.location.name,
          status: volume.status,
          server_id: volume.server&.id&.to_s,
          device_path: volume.linux_device
        )
      end

      def delete_volume(id)
        @client.volumes.find(id.to_i).destroy
      end

      def attach_volume(volume_id, server_id)
        volume = @client.volumes.find(volume_id.to_i)
        server = @client.servers.find(server_id.to_i)
        volume.attach(server: server)
      end

      def detach_volume(volume_id)
        volume = @client.volumes.find(volume_id.to_i)
        volume.detach
      end

      # Validation operations

      def validate_instance_type(instance_type)
        server_type = @client.server_types.to_a.find { |t| t.name == instance_type }
        raise ValidationError, "invalid hetzner server type: #{instance_type}" unless server_type

        true
      end

      def validate_region(region)
        location = @client.locations.to_a.find { |l| l.name == region }
        raise ValidationError, "invalid hetzner location: #{region}" unless location

        true
      end

      def validate_credentials
        # Test credentials by listing server types
        @client.server_types.to_a
        true
      rescue StandardError => e
        raise ValidationError, "hetzner credentials invalid: #{e.message}"
      end
    end
  end
end
