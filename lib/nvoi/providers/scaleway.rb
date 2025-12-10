# frozen_string_literal: true

require_relative "scaleway_client"

module Nvoi
  module Providers
    # Scaleway provider implements the compute provider interface for Scaleway Cloud
    class Scaleway < Base
      VALID_ZONES = %w[
        fr-par-1 fr-par-2 fr-par-3
        nl-ams-1 nl-ams-2 nl-ams-3
        pl-waw-1 pl-waw-2 pl-waw-3
      ].freeze

      def initialize(secret_key, project_id, zone: "fr-par-1")
        @client = ScalewayClient.new(secret_key, project_id, zone:)
        @project_id = project_id
        @zone = zone
      end

      # Network operations

      def find_or_create_network(name)
        network = find_network_by_name(name)
        return to_network(network) if network

        network = @client.create_private_network(
          name:,
          project_id: @project_id,
          subnets: [Constants::SUBNET_CIDR]
        )

        to_network(network)
      end

      def get_network_by_name(name)
        network = find_network_by_name(name)
        raise NetworkError, "network not found: #{name}" unless network

        to_network(network)
      end

      def delete_network(id)
        # First detach all servers from this network
        @client.list_servers.each do |server|
          nics = @client.list_private_nics(server["id"])
          nics.each do |nic|
            next unless nic["private_network_id"] == id

            @client.delete_private_nic(server["id"], nic["id"])
          rescue StandardError
            # Ignore cleanup errors
          end
        end

        @client.delete_private_network(id)
      end

      # Firewall operations (Security Groups)

      def find_or_create_firewall(name)
        sg = find_security_group_by_name(name)
        return to_firewall(sg) if sg

        sg = @client.create_security_group(
          name:,
          project: @project_id,
          stateful: true,
          inbound_default_policy: "drop",
          outbound_default_policy: "accept"
        )

        # Add SSH rule
        @client.create_security_group_rule(sg["id"], {
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
        raise FirewallError, "security group not found: #{name}" unless sg

        to_firewall(sg)
      end

      def delete_firewall(id)
        @client.delete_security_group(id)
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
        # Validate server type
        server_types = @client.list_server_types
        unless server_types.key?(opts.type)
          raise ValidationError, "invalid server type: #{opts.type}"
        end

        # Resolve image
        image = find_image(opts.image)
        raise ValidationError, "invalid image: #{opts.image}" unless image

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

        server = @client.create_server(create_opts)

        # Set cloud-init user data if provided
        if opts.user_data && !opts.user_data.empty?
          @client.set_user_data(server["id"], "cloud-init", opts.user_data)
        end

        # Power on the server
        @client.server_action(server["id"], "poweron")

        # Attach to private network if provided
        if opts.network_id && !opts.network_id.empty?
          # Wait for server to be running before attaching NIC
          wait_for_server_state(server["id"], "running", 30)
          @client.create_private_nic(server["id"], opts.network_id)
        end

        to_server(@client.get_server(server["id"]))
      end

      def wait_for_server(server_id, max_attempts)
        max_attempts.times do
          server = @client.get_server(server_id)

          if server["state"] == "running" && server.dig("public_ip", "address")
            return to_server(server)
          end

          sleep(Constants::SERVER_READY_INTERVAL)
        end

        raise ServerCreationError, "server did not become running after #{max_attempts} attempts"
      end

      def delete_server(id)
        # Delete private NICs first
        nics = @client.list_private_nics(id)
        nics.each do |nic|
          @client.delete_private_nic(id, nic["id"])
        rescue StandardError
          # Ignore cleanup errors
        end

        # Terminate server (this also stops and deletes)
        @client.server_action(id, "terminate")
      rescue StandardError => e
        # If terminate fails, try poweroff then delete
        begin
          @client.server_action(id, "poweroff")
          sleep(5)
          @client.delete_server(id)
        rescue StandardError
          raise e
        end
      end

      # Volume operations

      def create_volume(opts)
        server = @client.get_server(opts.server_id)
        raise VolumeError, "server not found: #{opts.server_id}" unless server

        volume = @client.create_volume(
          name: opts.name,
          perf_iops: 5000,
          from_empty: { size: opts.size * 1_000_000_000 },
          project_id: @project_id
        )

        to_volume(volume)
      end

      def get_volume(id)
        volume = @client.get_volume(id)
        return nil unless volume

        to_volume(volume)
      rescue NotFoundError
        nil
      end

      def get_volume_by_name(name)
        volume = @client.list_volumes.find { |v| v["name"] == name }
        return nil unless volume

        to_volume(volume)
      end

      def delete_volume(id)
        @client.delete_volume(id)
      end

      def attach_volume(volume_id, server_id)
        server = @client.get_server(server_id)
        raise VolumeError, "server not found: #{server_id}" unless server

        # Wait for volume to be available
        wait_for_volume_available(volume_id)

        # Get current volumes and add new one
        current_volumes = server["volumes"] || {}
        next_index = current_volumes.keys.map(&:to_i).max.to_i + 1

        new_volumes = current_volumes.dup
        # SBS volumes require volume_type: "sbs_volume"
        new_volumes[next_index.to_s] = { id: volume_id, volume_type: "sbs_volume" }

        @client.update_server(server_id, { volumes: new_volumes })
      end

      def wait_for_volume_available(volume_id, timeout: 60)
        deadline = Time.now + timeout
        loop do
          vol = @client.get_volume(volume_id)
          return if vol && vol["status"] == "available"

          raise VolumeError, "volume #{volume_id} did not become available" if Time.now > deadline

          sleep 2
        end
      end

      def detach_volume(volume_id)
        # Find which server has this volume
        @client.list_servers.each do |server|
          volumes = server["volumes"] || {}
          volumes.each do |idx, vol|
            next unless vol["id"] == volume_id

            # Remove this volume from the server
            new_volumes = volumes.reject { |k, _| k == idx }
            @client.update_server(server["id"], { volumes: new_volumes })
            return
          end
        end
      end

      # Validation operations

      def validate_instance_type(instance_type)
        server_types = @client.list_server_types
        unless server_types.key?(instance_type)
          raise ValidationError, "invalid scaleway server type: #{instance_type}"
        end

        true
      end

      def validate_region(region)
        unless VALID_ZONES.include?(region)
          raise ValidationError, "invalid scaleway zone: #{region}. Valid: #{VALID_ZONES.join(", ")}"
        end

        true
      end

      def validate_credentials
        @client.list_server_types
        true
      rescue AuthenticationError => e
        raise ValidationError, "scaleway credentials invalid: #{e.message}"
      end

      # Server IP lookup for exec/db commands
      def server_ip(server_name)
        server = find_server(server_name)
        server&.public_ipv4
      end

      private

        def find_network_by_name(name)
          @client.list_private_networks.find { |n| n["name"] == name }
        end

        def find_security_group_by_name(name)
          @client.list_security_groups.find { |sg| sg["name"] == name }
        end

        def find_server_by_name(name)
          @client.list_servers.find { |s| s["name"] == name }
        end

        def find_image(name)
          # Map common names to Scaleway equivalents
          image_name = case name
          when "ubuntu-24.04" then "ubuntu_noble"
          when "ubuntu-22.04" then "ubuntu_jammy"
          when "ubuntu-20.04" then "ubuntu_focal"
          when "debian-12" then "debian_bookworm"
          when "debian-11" then "debian_bullseye"
          else name
          end

          images = @client.list_images(name: image_name)
          images&.first
        end

        def wait_for_server_state(server_id, target_state, max_attempts)
          max_attempts.times do
            server = @client.get_server(server_id)
            return server if server["state"] == target_state

            sleep(2)
          end
          nil
        end

        def to_network(data)
          Network.new(
            id: data["id"],
            name: data["name"],
            ip_range: data.dig("subnets", 0, "subnet") || data["subnets"]&.first
          )
        end

        def to_firewall(data)
          Firewall.new(
            id: data["id"],
            name: data["name"]
          )
        end

        def to_server(data)
          Server.new(
            id: data["id"],
            name: data["name"],
            status: data["state"],
            public_ipv4: data.dig("public_ip", "address")
          )
        end

        def to_volume(data)
          # Find server_id from references if attached
          server_id = data["references"]&.find { |r|
            r["product_resource_type"] == "instance_server"
          }&.dig("product_resource_id")

          Volume.new(
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
