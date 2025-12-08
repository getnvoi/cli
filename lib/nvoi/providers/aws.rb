# frozen_string_literal: true

require "aws-sdk-ec2"

module Nvoi
  module Providers
    # AWS provider implements the compute provider interface for AWS EC2
    class AWS < Base
      def initialize(access_key_id, secret_access_key, region)
        @region = region || "us-east-1"
        @client = Aws::EC2::Client.new(
          region: @region,
          credentials: Aws::Credentials.new(access_key_id, secret_access_key)
        )
      end

      # Network operations

      def find_or_create_network(name)
        # Find existing VPC by tag
        vpc = find_vpc_by_name(name)
        if vpc
          return Network.new(
            id: vpc.vpc_id,
            name:,
            ip_range: vpc.cidr_block
          )
        end

        # Create new VPC
        create_resp = @client.create_vpc(
          cidr_block: "10.0.0.0/16",
          tag_specifications: [{
            resource_type: "vpc",
            tags: [{ key: "Name", value: name }]
          }]
        )
        vpc_id = create_resp.vpc.vpc_id

        # Enable DNS hostnames
        @client.modify_vpc_attribute(
          vpc_id:,
          enable_dns_hostnames: { value: true }
        )

        # Create subnet
        subnet_resp = @client.create_subnet(
          vpc_id:,
          cidr_block: "10.0.1.0/24",
          tag_specifications: [{
            resource_type: "subnet",
            tags: [{ key: "Name", value: "#{name}-subnet" }]
          }]
        )

        # Create internet gateway
        igw_resp = @client.create_internet_gateway(
          tag_specifications: [{
            resource_type: "internet-gateway",
            tags: [{ key: "Name", value: "#{name}-igw" }]
          }]
        )
        igw_id = igw_resp.internet_gateway.internet_gateway_id

        # Attach internet gateway to VPC
        @client.attach_internet_gateway(vpc_id:, internet_gateway_id: igw_id)

        # Create route table
        rtb_resp = @client.create_route_table(
          vpc_id:,
          tag_specifications: [{
            resource_type: "route-table",
            tags: [{ key: "Name", value: "#{name}-rtb" }]
          }]
        )
        rtb_id = rtb_resp.route_table.route_table_id

        # Add route to internet gateway
        @client.create_route(
          route_table_id: rtb_id,
          destination_cidr_block: "0.0.0.0/0",
          gateway_id: igw_id
        )

        # Associate route table with subnet
        @client.associate_route_table(
          route_table_id: rtb_id,
          subnet_id: subnet_resp.subnet.subnet_id
        )

        Network.new(
          id: vpc_id,
          name:,
          ip_range: create_resp.vpc.cidr_block
        )
      end

      def get_network_by_name(name)
        vpc = find_vpc_by_name(name)
        raise NetworkError, "network not found: #{name}" unless vpc

        Network.new(
          id: vpc.vpc_id,
          name:,
          ip_range: vpc.cidr_block
        )
      end

      def delete_network(id)
        @client.delete_vpc(vpc_id: id)
      end

      # Firewall operations

      def find_or_create_firewall(name)
        # Find existing security group
        sg = find_security_group_by_name(name)
        if sg
          return Firewall.new(id: sg.group_id, name:)
        end

        # Get default VPC
        vpcs = @client.describe_vpcs(filters: [{ name: "isDefault", values: ["true"] }])
        raise NetworkError, "no default VPC found" if vpcs.vpcs.empty?

        # Create security group
        create_resp = @client.create_security_group(
          group_name: name,
          description: "Managed by nvoi",
          vpc_id: vpcs.vpcs[0].vpc_id,
          tag_specifications: [{
            resource_type: "security-group",
            tags: [{ key: "Name", value: name }]
          }]
        )

        # Add SSH ingress rule
        @client.authorize_security_group_ingress(
          group_id: create_resp.group_id,
          ip_permissions: [{
            ip_protocol: "tcp",
            from_port: 22,
            to_port: 22,
            ip_ranges: [{ cidr_ip: "0.0.0.0/0" }]
          }]
        )

        Firewall.new(id: create_resp.group_id, name:)
      end

      def get_firewall_by_name(name)
        sg = find_security_group_by_name(name)
        raise FirewallError, "firewall not found: #{name}" unless sg

        Firewall.new(id: sg.group_id, name:)
      end

      def delete_firewall(id)
        @client.delete_security_group(group_id: id)
      end

      # Server operations

      def find_server(name)
        instance = find_instance_by_name(name)
        return nil unless instance

        instance_to_server(instance)
      end

      def list_servers
        result = @client.describe_instances(
          filters: [{
            name: "instance-state-name",
            values: %w[pending running stopping stopped]
          }]
        )

        servers = []
        result.reservations.each do |reservation|
          reservation.instances.each do |instance|
            servers << instance_to_server(instance)
          end
        end
        servers
      end

      def create_server(opts)
        # Get AMI ID for Ubuntu 22.04
        ami_id = get_ubuntu_ami

        input = {
          image_id: ami_id,
          instance_type: opts.type,
          min_count: 1,
          max_count: 1,
          user_data: opts.user_data ? Base64.encode64(opts.user_data) : nil,
          tag_specifications: [{
            resource_type: "instance",
            tags: [{ key: "Name", value: opts.name }]
          }]
        }

        # Add network configuration if provided
        if opts.network_id && !opts.network_id.empty?
          subnets = @client.describe_subnets(
            filters: [{ name: "vpc-id", values: [opts.network_id] }]
          )
          input[:subnet_id] = subnets.subnets[0].subnet_id unless subnets.subnets.empty?
        end

        # Add security group if provided
        if opts.firewall_id && !opts.firewall_id.empty?
          input[:security_group_ids] = [opts.firewall_id]
        end

        result = @client.run_instances(input)
        raise ServerCreationError, "no instance created" if result.instances.empty?

        instance_to_server(result.instances[0])
      end

      def wait_for_server(server_id, max_attempts)
        max_attempts.times do
          resp = @client.describe_instances(instance_ids: [server_id])

          if resp.reservations.any? && resp.reservations[0].instances.any?
            instance = resp.reservations[0].instances[0]
            return instance_to_server(instance) if instance.state.name == "running"
          end

          sleep(5)
        end

        raise ServerCreationError, "instance did not become running after #{max_attempts} attempts"
      end

      def delete_server(id)
        @client.terminate_instances(instance_ids: [id])
      end

      # Volume operations

      def create_volume(opts)
        # Get instance to derive availability zone
        resp = @client.describe_instances(instance_ids: [opts.server_id])
        raise VolumeError, "instance not found: #{opts.server_id}" if resp.reservations.empty?

        instance = resp.reservations[0].instances[0]
        az = instance.placement.availability_zone

        create_resp = @client.create_volume(
          availability_zone: az,
          size: opts.size,
          volume_type: "gp3",
          tag_specifications: [{
            resource_type: "volume",
            tags: [{ key: "Name", value: opts.name }]
          }]
        )

        Volume.new(
          id: create_resp.volume_id,
          name: opts.name,
          size: create_resp.size,
          location: create_resp.availability_zone,
          status: create_resp.state
        )
      end

      def get_volume(id)
        resp = @client.describe_volumes(volume_ids: [id])
        return nil if resp.volumes.empty?

        volume_to_compute(resp.volumes[0])
      end

      def get_volume_by_name(name)
        resp = @client.describe_volumes(
          filters: [{ name: "tag:Name", values: [name] }]
        )
        return nil if resp.volumes.empty?

        volume_to_compute(resp.volumes[0])
      end

      def delete_volume(id)
        @client.delete_volume(volume_id: id)
      end

      def attach_volume(volume_id, server_id)
        @client.attach_volume(
          volume_id:,
          instance_id: server_id,
          device: "/dev/xvdf"
        )
      end

      def detach_volume(volume_id)
        @client.detach_volume(volume_id:)
      end

      # Validation operations

      def validate_instance_type(instance_type)
        resp = @client.describe_instance_types(instance_types: [instance_type])
        raise ValidationError, "invalid AWS instance type: #{instance_type}" if resp.instance_types.empty?

        true
      end

      def validate_region(region)
        resp = @client.describe_regions(region_names: [region])
        raise ValidationError, "invalid AWS region: #{region}" if resp.regions.empty?

        true
      end

      def validate_credentials
        @client.describe_regions
        true
      rescue StandardError => e
        raise ValidationError, "aws credentials invalid: #{e.message}"
      end

      private

        def find_vpc_by_name(name)
          resp = @client.describe_vpcs(
            filters: [{ name: "tag:Name", values: [name] }]
          )
          resp.vpcs.first
        end

        def find_security_group_by_name(name)
          resp = @client.describe_security_groups(
            filters: [{ name: "group-name", values: [name] }]
          )
          resp.security_groups.first
        end

        def find_instance_by_name(name)
          resp = @client.describe_instances(
            filters: [
              { name: "tag:Name", values: [name] },
              { name: "instance-state-name", values: %w[pending running stopping stopped] }
            ]
          )

          resp.reservations.each do |reservation|
            return reservation.instances.first unless reservation.instances.empty?
          end
          nil
        end

        def get_ubuntu_ami
          resp = @client.describe_images(
            owners: ["099720109477"], # Canonical's AWS account ID
            filters: [
              { name: "name", values: ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"] },
              { name: "state", values: ["available"] }
            ]
          )

          raise ProviderError, "no Ubuntu 22.04 AMI found" if resp.images.empty?

          # Return the most recent AMI
          latest = resp.images.max_by(&:creation_date)
          latest.image_id
        end

        def instance_to_server(instance)
          name = instance.tags&.find { |t| t.key == "Name" }&.value || ""

          Server.new(
            id: instance.instance_id,
            name:,
            status: instance.state.name,
            public_ipv4: instance.public_ip_address
          )
        end

        def volume_to_compute(vol)
          name = vol.tags&.find { |t| t.key == "Name" }&.value || ""

          v = Volume.new(
            id: vol.volume_id,
            name:,
            size: vol.size,
            location: vol.availability_zone,
            status: vol.state
          )

          if vol.attachments.any?
            v.server_id = vol.attachments[0].instance_id
            v.device_path = vol.attachments[0].device
          end

          v
        end
    end
  end
end
