# frozen_string_literal: true

require "test_helper"
require "aws-sdk-ec2"

class AWSCloudTest < Minitest::Test
  def setup
    Aws.config.update(stub_responses: true)
    @provider = Nvoi::External::Cloud::AWS.new("fake-key", "fake-secret", "us-east-1")
    @client = @provider.instance_variable_get(:@client)
  end

  def teardown
    Aws.config.update(stub_responses: false)
  end

  # Network tests

  def test_find_or_create_network_returns_existing
    @client.stub_responses(:describe_vpcs, {
      vpcs: [{ vpc_id: "vpc-123", cidr_block: "10.0.0.0/16", tags: [{ key: "Name", value: "test-network" }] }]
    })

    network = @provider.find_or_create_network("test-network")

    assert_equal "vpc-123", network.id
    assert_equal "test-network", network.name
    assert_equal "10.0.0.0/16", network.ip_range
  end

  def test_get_network_by_name_raises_when_not_found
    @client.stub_responses(:describe_vpcs, { vpcs: [] })

    assert_raises(Nvoi::NetworkError) do
      @provider.get_network_by_name("nonexistent")
    end
  end

  def test_get_network_by_name_success
    @client.stub_responses(:describe_vpcs, {
      vpcs: [{ vpc_id: "vpc-456", cidr_block: "10.0.0.0/16", tags: [{ key: "Name", value: "my-net" }] }]
    })

    network = @provider.get_network_by_name("my-net")

    assert_equal "vpc-456", network.id
    assert_equal "my-net", network.name
  end

  def test_delete_network
    @client.stub_responses(:delete_vpc, {})
    @provider.delete_network("vpc-789")
  end

  # Firewall tests

  def test_find_or_create_firewall_returns_existing
    @client.stub_responses(:describe_security_groups, {
      security_groups: [{ group_id: "sg-123", group_name: "test-fw" }]
    })

    firewall = @provider.find_or_create_firewall("test-fw")

    assert_equal "sg-123", firewall.id
    assert_equal "test-fw", firewall.name
  end

  def test_get_firewall_by_name_raises_when_not_found
    @client.stub_responses(:describe_security_groups, { security_groups: [] })

    assert_raises(Nvoi::FirewallError) do
      @provider.get_firewall_by_name("nonexistent")
    end
  end

  def test_get_firewall_by_name_success
    @client.stub_responses(:describe_security_groups, {
      security_groups: [{ group_id: "sg-456", group_name: "my-fw" }]
    })

    firewall = @provider.get_firewall_by_name("my-fw")

    assert_equal "sg-456", firewall.id
    assert_equal "my-fw", firewall.name
  end

  def test_delete_firewall
    @client.stub_responses(:delete_security_group, {})
    @provider.delete_firewall("sg-789")
  end

  # Server tests

  def test_find_server_returns_nil_when_not_found
    @client.stub_responses(:describe_instances, { reservations: [] })

    server = @provider.find_server("nonexistent")

    assert_nil server
  end

  def test_find_server_returns_server_when_found
    @client.stub_responses(:describe_instances, {
      reservations: [{
        instances: [{
          instance_id: "i-123",
          tags: [{ key: "Name", value: "test-server" }],
          state: { name: "running" },
          public_ip_address: "1.2.3.4"
        }]
      }]
    })

    server = @provider.find_server("test-server")

    assert_equal "i-123", server.id
    assert_equal "test-server", server.name
    assert_equal "running", server.status
    assert_equal "1.2.3.4", server.public_ipv4
  end

  def test_list_servers
    @client.stub_responses(:describe_instances, {
      reservations: [{
        instances: [
          { instance_id: "i-1", tags: [{ key: "Name", value: "srv-1" }], state: { name: "running" }, public_ip_address: "1.1.1.1" },
          { instance_id: "i-2", tags: [{ key: "Name", value: "srv-2" }], state: { name: "stopped" }, public_ip_address: nil }
        ]
      }]
    })

    servers = @provider.list_servers

    assert_equal 2, servers.size
    assert_equal "srv-1", servers[0].name
    assert_equal "srv-2", servers[1].name
  end

  def test_delete_server
    @client.stub_responses(:terminate_instances, {})
    @provider.delete_server("i-999")
  end

  # Volume tests

  def test_get_volume_returns_nil_when_empty
    @client.stub_responses(:describe_volumes, { volumes: [] })

    volume = @provider.get_volume("vol-999")

    assert_nil volume
  end

  def test_get_volume_returns_volume
    @client.stub_responses(:describe_volumes, {
      volumes: [{
        volume_id: "vol-123",
        tags: [{ key: "Name", value: "my-vol" }],
        size: 50,
        availability_zone: "us-east-1a",
        state: "available",
        attachments: []
      }]
    })

    volume = @provider.get_volume("vol-123")

    assert_equal "vol-123", volume.id
    assert_equal "my-vol", volume.name
    assert_equal 50, volume.size
    assert_equal "us-east-1a", volume.location
  end

  def test_get_volume_by_name_returns_nil_when_not_found
    @client.stub_responses(:describe_volumes, { volumes: [] })

    volume = @provider.get_volume_by_name("nonexistent")

    assert_nil volume
  end

  def test_get_volume_by_name_returns_volume
    @client.stub_responses(:describe_volumes, {
      volumes: [{
        volume_id: "vol-456",
        tags: [{ key: "Name", value: "test-vol" }],
        size: 20,
        availability_zone: "us-east-1b",
        state: "in-use",
        attachments: [{ instance_id: "i-111", device: "/dev/xvdf" }]
      }]
    })

    volume = @provider.get_volume_by_name("test-vol")

    assert_equal "vol-456", volume.id
    assert_equal "test-vol", volume.name
    assert_equal "i-111", volume.server_id
  end

  def test_delete_volume
    @client.stub_responses(:delete_volume, {})
    @provider.delete_volume("vol-789")
  end

  def test_attach_volume
    @client.stub_responses(:attach_volume, {})
    @provider.attach_volume("vol-100", "i-200")
  end

  def test_detach_volume
    @client.stub_responses(:detach_volume, {})
    @provider.detach_volume("vol-100")
  end

  # Validation tests

  def test_validate_instance_type_success
    @client.stub_responses(:describe_instance_types, {
      instance_types: [{ instance_type: "t3.micro" }]
    })

    assert @provider.validate_instance_type("t3.micro")
  end

  def test_validate_instance_type_failure
    @client.stub_responses(:describe_instance_types, { instance_types: [] })

    assert_raises(Nvoi::ValidationError) do
      @provider.validate_instance_type("invalid-type")
    end
  end

  def test_validate_region_success
    @client.stub_responses(:describe_regions, {
      regions: [{ region_name: "us-west-2" }]
    })

    assert @provider.validate_region("us-west-2")
  end

  def test_validate_region_failure
    @client.stub_responses(:describe_regions, { regions: [] })

    assert_raises(Nvoi::ValidationError) do
      @provider.validate_region("invalid-region")
    end
  end

  def test_validate_credentials_success
    @client.stub_responses(:describe_regions, { regions: [] })

    assert @provider.validate_credentials
  end

  def test_validate_credentials_failure
    @client.stub_responses(:describe_regions, "UnauthorizedOperation")

    assert_raises(Nvoi::ValidationError) do
      @provider.validate_credentials
    end
  end

  # Create operations tests

  def test_find_or_create_network_creates_new
    @client.stub_responses(:describe_vpcs, { vpcs: [] })
    @client.stub_responses(:create_vpc, {
      vpc: { vpc_id: "vpc-new", cidr_block: "10.0.0.0/16" }
    })
    @client.stub_responses(:modify_vpc_attribute, {})
    @client.stub_responses(:create_subnet, {
      subnet: { subnet_id: "subnet-123" }
    })
    @client.stub_responses(:create_internet_gateway, {
      internet_gateway: { internet_gateway_id: "igw-123" }
    })
    @client.stub_responses(:attach_internet_gateway, {})
    @client.stub_responses(:create_route_table, {
      route_table: { route_table_id: "rtb-123" }
    })
    @client.stub_responses(:create_route, {})
    @client.stub_responses(:associate_route_table, {})

    network = @provider.find_or_create_network("new-network")

    assert_equal "vpc-new", network.id
    assert_equal "new-network", network.name
  end

  def test_find_or_create_firewall_creates_new
    @client.stub_responses(:describe_security_groups, { security_groups: [] })
    @client.stub_responses(:describe_vpcs, {
      vpcs: [{ vpc_id: "vpc-default", is_default: true }]
    })
    @client.stub_responses(:create_security_group, { group_id: "sg-new" })
    @client.stub_responses(:authorize_security_group_ingress, {})

    firewall = @provider.find_or_create_firewall("new-firewall")

    assert_equal "sg-new", firewall.id
    assert_equal "new-firewall", firewall.name
  end

  def test_create_server
    @client.stub_responses(:describe_images, {
      images: [{ image_id: "ami-123", creation_date: "2024-01-01" }]
    })
    @client.stub_responses(:run_instances, {
      instances: [{
        instance_id: "i-new",
        tags: [{ key: "Name", value: "new-server" }],
        state: { name: "pending" },
        public_ip_address: nil
      }]
    })

    opts = Nvoi::Objects::ServerCreateOptions.new(
      name: "new-server",
      type: "t3.micro",
      location: "us-east-1"
    )
    server = @provider.create_server(opts)

    assert_equal "i-new", server.id
    assert_equal "new-server", server.name
    assert_equal "pending", server.status
  end

  def test_create_server_with_network_and_firewall
    @client.stub_responses(:describe_images, {
      images: [{ image_id: "ami-123", creation_date: "2024-01-01" }]
    })
    @client.stub_responses(:describe_subnets, {
      subnets: [{ subnet_id: "subnet-123" }]
    })
    @client.stub_responses(:run_instances, {
      instances: [{
        instance_id: "i-new2",
        tags: [{ key: "Name", value: "new-server2" }],
        state: { name: "pending" },
        public_ip_address: nil
      }]
    })

    opts = Nvoi::Objects::ServerCreateOptions.new(
      name: "new-server2",
      type: "t3.micro",
      location: "us-east-1",
      network_id: "vpc-123",
      firewall_id: "sg-456"
    )
    server = @provider.create_server(opts)

    assert_equal "i-new2", server.id
  end

  def test_create_volume
    @client.stub_responses(:describe_instances, {
      reservations: [{
        instances: [{
          instance_id: "i-123",
          placement: { availability_zone: "us-east-1a" },
          tags: [],
          state: { name: "running" }
        }]
      }]
    })
    @client.stub_responses(:create_volume, {
      volume_id: "vol-new",
      size: 50,
      availability_zone: "us-east-1a",
      state: "creating"
    })

    opts = Nvoi::Objects::VolumeCreateOptions.new(
      name: "new-volume",
      size: 50,
      server_id: "i-123"
    )
    volume = @provider.create_volume(opts)

    assert_equal "vol-new", volume.id
    assert_equal "new-volume", volume.name
    assert_equal 50, volume.size
  end

  def test_create_volume_raises_when_instance_not_found
    @client.stub_responses(:describe_instances, { reservations: [] })

    opts = Nvoi::Objects::VolumeCreateOptions.new(
      name: "vol",
      size: 10,
      server_id: "i-nonexistent"
    )

    assert_raises(Nvoi::VolumeError) do
      @provider.create_volume(opts)
    end
  end

  def test_create_server_raises_when_no_instance_created
    @client.stub_responses(:describe_images, {
      images: [{ image_id: "ami-123", creation_date: "2024-01-01" }]
    })
    @client.stub_responses(:run_instances, { instances: [] })

    opts = Nvoi::Objects::ServerCreateOptions.new(
      name: "test",
      type: "t3.micro",
      location: "us-east-1"
    )

    assert_raises(Nvoi::ServerCreationError) do
      @provider.create_server(opts)
    end
  end

  def test_get_ubuntu_ami_raises_when_no_ami_found
    @client.stub_responses(:describe_images, { images: [] })

    opts = Nvoi::Objects::ServerCreateOptions.new(
      name: "test",
      type: "t3.micro",
      location: "us-east-1"
    )

    assert_raises(Nvoi::ProviderError) do
      @provider.create_server(opts)
    end
  end

  def test_find_or_create_firewall_raises_when_no_default_vpc
    @client.stub_responses(:describe_security_groups, { security_groups: [] })
    @client.stub_responses(:describe_vpcs, { vpcs: [] })

    assert_raises(Nvoi::NetworkError) do
      @provider.find_or_create_firewall("test-fw")
    end
  end
end
