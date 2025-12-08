# frozen_string_literal: true

require "test_helper"

# Mock hcloud gem behavior - collections have find(id) not find(&block)
class MockHcloudCollection
  def initialize(items)
    @items = items
  end

  def to_a
    @items
  end

  def each(&block)
    @items.each(&block)
  end

  def map(&block)
    @items.map(&block)
  end

  def find(id = nil, &block)
    if block_given? && id.nil?
      raise ArgumentError, "wrong number of arguments (given 0, expected 1)"
    end
    @items.find { |i| i.id == id }
  end

  def create(**opts)
    @item_class ||= MockHcloudResource
    valid_keys = @item_class.members
    filtered = opts.select { |k, _| valid_keys.include?(k) }
    @item_class.new(id: rand(1000..9999), **filtered)
  end

  def with_item_class(klass)
    @item_class = klass
    self
  end
end

MockHcloudResource = Struct.new(:id, :name, :description, :public_net, :status, :datacenter, :private_net, keyword_init: true) do
  def destroy; end
  def actions; MockHcloudActions.new; end
  def detach_from_network(network:); end
end

MockHcloudActions = Struct.new(:values) do
  def initialize
    super([])
  end
end

MockHcloudServerType = Struct.new(:id, :name, :description, :cores, :memory, :disk, keyword_init: true)
MockHcloudLocation = Struct.new(:id, :name, :description, :country, :city, keyword_init: true)
MockHcloudImage = Struct.new(:id, :name, :description, :type, keyword_init: true)
MockHcloudNetwork = Struct.new(:id, :name, :ip_range, keyword_init: true)
MockHcloudFirewall = Struct.new(:id, :name, :rules, :applied_to, keyword_init: true) do
  def remove_target(type:, server:); end
end
MockHcloudVolume = Struct.new(:id, :name, :size, :server, :location, :status, :linux_device, keyword_init: true) do
  def attach(server:, automount: true); end
  def detach; end
end

MockHcloudPublicNet = Struct.new(:ipv4, keyword_init: true)
MockHcloudIpv4 = Struct.new(:ip, keyword_init: true)
MockHcloudDatacenter = Struct.new(:location, keyword_init: true)

class MockHcloudClient
  attr_reader :server_types, :locations, :images, :networks, :firewalls, :servers, :volumes

  def initialize
    @server_types = MockHcloudCollection.new([
      MockHcloudServerType.new(id: 1, name: "cx22", cores: 2, memory: 4, disk: 40),
      MockHcloudServerType.new(id: 2, name: "cx32", cores: 4, memory: 8, disk: 80),
      MockHcloudServerType.new(id: 3, name: "cx42", cores: 8, memory: 16, disk: 160)
    ]).with_item_class(MockHcloudServerType)
    @locations = MockHcloudCollection.new([
      MockHcloudLocation.new(id: 1, name: "fsn1", country: "DE", city: "Falkenstein"),
      MockHcloudLocation.new(id: 2, name: "nbg1", country: "DE", city: "Nuremberg"),
      MockHcloudLocation.new(id: 3, name: "hel1", country: "FI", city: "Helsinki")
    ]).with_item_class(MockHcloudLocation)
    @images = MockHcloudCollection.new([
      MockHcloudImage.new(id: 1, name: "ubuntu-22.04", type: "system"),
      MockHcloudImage.new(id: 2, name: "debian-12", type: "system")
    ]).with_item_class(MockHcloudImage)
    @networks = MockHcloudCollection.new([]).with_item_class(MockHcloudNetwork)
    @firewalls = MockHcloudCollection.new([]).with_item_class(MockHcloudFirewall)
    @servers = MockHcloudCollection.new([]).with_item_class(MockHcloudResource)
    @volumes = MockHcloudCollection.new([]).with_item_class(MockHcloudVolume)
  end

  def add_network(network)
    @networks = MockHcloudCollection.new(@networks.to_a + [network])
  end

  def add_firewall(firewall)
    @firewalls = MockHcloudCollection.new(@firewalls.to_a + [firewall])
  end

  def add_server(server)
    @servers = MockHcloudCollection.new(@servers.to_a + [server])
  end

  def add_volume(volume)
    @volumes = MockHcloudCollection.new(@volumes.to_a + [volume])
  end
end

class Nvoi::Providers::HetznerTest < Minitest::Test
  def setup
    @mock_client = MockHcloudClient.new
    @provider = Nvoi::Providers::Hetzner.new("test-api-token")
    @provider.instance_variable_set(:@client, @mock_client)
  end

  # Validation tests - these would have caught the bug

  def test_validate_instance_type_valid
    assert @provider.validate_instance_type("cx22")
    assert @provider.validate_instance_type("cx32")
  end

  def test_validate_instance_type_invalid
    error = assert_raises(Nvoi::ValidationError) do
      @provider.validate_instance_type("invalid-type")
    end
    assert_match(/invalid hetzner server type/, error.message)
  end

  def test_validate_region_valid
    assert @provider.validate_region("fsn1")
    assert @provider.validate_region("nbg1")
  end

  def test_validate_region_invalid
    error = assert_raises(Nvoi::ValidationError) do
      @provider.validate_region("invalid-region")
    end
    assert_match(/invalid hetzner location/, error.message)
  end

  def test_validate_credentials
    assert @provider.validate_credentials
  end

  # Network operations

  def test_find_or_create_network_creates_when_not_found
    network = @provider.find_or_create_network("test-network")
    refute_nil network
    assert_kind_of Nvoi::Providers::Network, network
  end

  def test_find_or_create_network_finds_existing
    existing = MockHcloudNetwork.new(id: 123, name: "existing-network", ip_range: "10.0.0.0/16")
    @mock_client.add_network(existing)

    network = @provider.find_or_create_network("existing-network")
    assert_equal "123", network.id
  end

  # Firewall operations

  def test_find_or_create_firewall_creates_when_not_found
    firewall = @provider.find_or_create_firewall("test-firewall")
    refute_nil firewall
    assert_kind_of Nvoi::Providers::Firewall, firewall
  end

  def test_find_or_create_firewall_finds_existing
    existing = MockHcloudFirewall.new(id: 456, name: "existing-fw", rules: [])
    @mock_client.add_firewall(existing)

    firewall = @provider.find_or_create_firewall("existing-fw")
    assert_equal "456", firewall.id
  end

  # Server operations

  def test_find_server_returns_nil_when_not_found
    server = @provider.find_server("nonexistent")
    assert_nil server
  end

  def test_find_server_returns_server_when_found
    existing = MockHcloudResource.new(
      id: 789,
      name: "my-server",
      public_net: MockHcloudPublicNet.new(ipv4: MockHcloudIpv4.new(ip: "1.2.3.4")),
      status: "running"
    )
    @mock_client.add_server(existing)

    server = @provider.find_server("my-server")
    refute_nil server
    assert_equal "789", server.id
    assert_equal "1.2.3.4", server.public_ipv4
  end

  def test_list_servers
    server1 = MockHcloudResource.new(
      id: 1, name: "server-1",
      public_net: MockHcloudPublicNet.new(ipv4: MockHcloudIpv4.new(ip: "1.1.1.1")),
      status: "running"
    )
    server2 = MockHcloudResource.new(
      id: 2, name: "server-2",
      public_net: MockHcloudPublicNet.new(ipv4: MockHcloudIpv4.new(ip: "2.2.2.2")),
      status: "running"
    )
    @mock_client.add_server(server1)
    @mock_client.add_server(server2)

    servers = @provider.list_servers
    assert_equal 2, servers.length
  end

  # Volume operations

  def test_get_volume_by_name_returns_nil_when_not_found
    volume = @provider.get_volume_by_name("nonexistent")
    assert_nil volume
  end

  def test_get_volume_by_name_returns_volume_when_found
    existing = MockHcloudVolume.new(
      id: 111,
      name: "existing-vol",
      size: 20,
      location: MockHcloudLocation.new(name: "fsn1"),
      status: "available",
      linux_device: "/dev/sdb"
    )
    @mock_client.add_volume(existing)

    volume = @provider.get_volume_by_name("existing-vol")
    refute_nil volume
    assert_equal "111", volume.id
  end
end

# Test that MockHcloudCollection mimics real hcloud behavior
class MockHcloudCollectionBehaviorTest < Minitest::Test
  def test_find_without_argument_raises_error
    collection = MockHcloudCollection.new([])
    assert_raises(ArgumentError) do
      collection.find { |x| x }
    end
  end

  def test_to_a_find_with_block_works
    items = [
      MockHcloudServerType.new(id: 1, name: "cx22"),
      MockHcloudServerType.new(id: 2, name: "cx32")
    ]
    collection = MockHcloudCollection.new(items)

    result = collection.to_a.find { |t| t.name == "cx32" }
    refute_nil result
    assert_equal 2, result.id
  end
end
