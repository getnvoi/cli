# frozen_string_literal: true

require "aws-sdk-ec2"
require "base64"

module Nvoi
  module External
    module Cloud
      # AWS provider implements the compute provider interface for AWS EC2
      class Aws < Base
        def initialize(access_key_id, secret_access_key, region)
          @region = region || "us-east-1"
          @client = ::Aws::EC2::Client.new(
            region: @region,
            credentials: ::Aws::Credentials.new(access_key_id, secret_access_key)
          )
        end

        # Network operations

        def find_or_create_network(name)
          vpc = find_vpc_by_name(name)
          if vpc
            return Types::Network::Record.new(
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

          Types::Network::Record.new(
            id: vpc_id,
            name:,
            ip_range: create_resp.vpc.cidr_block
          )
        end

        def get_network_by_name(name)
          vpc = find_vpc_by_name(name)
          raise Errors::NetworkError, "network not found: #{name}" unless vpc

          Types::Network::Record.new(
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
          sg = find_security_group_by_name(name)
          if sg
            return Types::Firewall::Record.new(id: sg.group_id, name:)
          end

          # Get default VPC
          vpcs = @client.describe_vpcs(filters: [{ name: "isDefault", values: ["true"] }])
          raise Errors::NetworkError, "no default VPC found" if vpcs.vpcs.empty?

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

          Types::Firewall::Record.new(id: create_resp.group_id, name:)
        end

        def get_firewall_by_name(name)
          sg = find_security_group_by_name(name)
          raise Errors::FirewallError, "firewall not found: #{name}" unless sg

          Types::Firewall::Record.new(id: sg.group_id, name:)
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

        def find_server_by_id(id)
          result = @client.describe_instances(instance_ids: [id])
          return nil if result.reservations.empty? || result.reservations[0].instances.empty?

          instance_to_server(result.reservations[0].instances[0])
        rescue ::Aws::EC2::Errors::InvalidInstanceIDNotFound
          nil
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
          unless opts.network_id.blank?
            subnets = @client.describe_subnets(
              filters: [{ name: "vpc-id", values: [opts.network_id] }]
            )
            input[:subnet_id] = subnets.subnets[0].subnet_id unless subnets.subnets.empty?
          end

          # Add security group if provided
          unless opts.firewall_id.blank?
            input[:security_group_ids] = [opts.firewall_id]
          end

          result = @client.run_instances(input)
          raise Errors::ServerCreationError, "no instance created" if result.instances.empty?

          instance_to_server(result.instances[0])
        end

        def wait_for_server(server_id, max_attempts)
          server = Utils::Retry.poll(max_attempts:, interval: 5) do
            resp = @client.describe_instances(instance_ids: [server_id])

            if resp.reservations.any? && resp.reservations[0].instances.any?
              instance = resp.reservations[0].instances[0]
              instance_to_server(instance) if instance.state.name == "running"
            end
          end

          raise Errors::ServerCreationError, "instance did not become running after #{max_attempts} attempts" unless server

          server
        end

        def delete_server(id)
          @client.terminate_instances(instance_ids: [id])
        end

        # Volume operations

        def create_volume(opts)
          resp = @client.describe_instances(instance_ids: [opts.server_id])
          raise Errors::VolumeError, "instance not found: #{opts.server_id}" if resp.reservations.empty?

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

          Types::Volume::Record.new(
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

          volume_to_object(resp.volumes[0])
        end

        def get_volume_by_name(name)
          resp = @client.describe_volumes(
            filters: [{ name: "tag:Name", values: [name] }]
          )
          return nil if resp.volumes.empty?

          volume_to_object(resp.volumes[0])
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

        def wait_for_device_path(volume_id, _ssh)
          # AWS provides device path in attachment info
          Utils::Retry.poll(max_attempts: 30, interval: 2) do
            resp = @client.describe_volumes(volume_ids: [volume_id])
            next nil if resp.volumes.empty?

            vol = resp.volumes[0]
            next nil if vol.attachments.empty?

            device = vol.attachments[0].device
            device unless device.blank?
          end
        end

        # Validation operations

        def validate_instance_type(instance_type)
          resp = @client.describe_instance_types(instance_types: [instance_type])
          raise Errors::ValidationError, "invalid AWS instance type: #{instance_type}" if resp.instance_types.empty?

          true
        end

        def validate_region(region)
          resp = @client.describe_regions(region_names: [region])
          raise Errors::ValidationError, "invalid AWS region: #{region}" if resp.regions.empty?

          true
        end

        def validate_credentials
          @client.describe_regions
          true
        rescue StandardError => e
          raise Errors::ValidationError, "aws credentials invalid: #{e.message}"
        end

        # List available instance types for onboarding
        def list_instance_types
          # Common instance types (full list is huge)
          common_types = %w[t3.micro t3.small t3.medium t3.large t3.xlarge m5.large m5.xlarge c5.large c5.xlarge]
          resp = @client.describe_instance_types(instance_types: common_types)
          resp.instance_types.map do |t|
            {
              name: t.instance_type,
              vcpus: t.v_cpu_info.default_v_cpus,
              memory: t.memory_info.size_in_mi_b
            }
          end
        rescue StandardError
          # Fallback to static list if API fails
          common_types.map { |t| { name: t, vcpus: nil, memory: nil } }
        end

        # List available regions for onboarding
        def list_regions
          resp = @client.describe_regions
          resp.regions.map do |r|
            { name: r.region_name, endpoint: r.endpoint }
          end
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

            raise Errors::ProviderError, "no Ubuntu 22.04 AMI found" if resp.images.empty?

            latest = resp.images.max_by(&:creation_date)
            latest.image_id
          end

          def instance_to_server(instance)
            name = instance.tags&.find { |t| t.key == "Name" }&.value || ""

            Types::Server::Record.new(
              id: instance.instance_id,
              name:,
              status: instance.state.name,
              public_ipv4: instance.public_ip_address,
              private_ipv4: instance.private_ip_address
            )
          end

          def volume_to_object(vol)
            name = vol.tags&.find { |t| t.key == "Name" }&.value || ""

            v = Types::Volume::Record.new(
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
end
