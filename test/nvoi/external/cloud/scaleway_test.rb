# frozen_string_literal: true

require "test_helper"
require "webmock/minitest"

class ScalewayCloudTest < Minitest::Test
  def setup
    WebMock.disable_net_connect!
    @provider = Nvoi::External::Cloud::Scaleway.new("test-secret", "proj-123", zone: "fr-par-1")
  end

  def teardown
    WebMock.reset!
  end

  def test_zone_and_region
    assert_equal "fr-par-1", @provider.zone
    assert_equal "fr-par", @provider.region
    assert_equal "proj-123", @provider.project_id
  end

  # Network tests

  def test_find_or_create_network_returns_existing
    stub_request(:get, "https://api.scaleway.com/vpc/v2/regions/fr-par/private-networks")
      .to_return(status: 200, body: {
        private_networks: [{ id: "net-123", name: "test-network", subnets: [{ subnet: "10.0.1.0/24" }] }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    network = @provider.find_or_create_network("test-network")

    assert_equal "net-123", network.id
    assert_equal "test-network", network.name
  end

  def test_find_or_create_network_creates_new
    stub_request(:get, "https://api.scaleway.com/vpc/v2/regions/fr-par/private-networks")
      .to_return(status: 200, body: { private_networks: [] }.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:post, "https://api.scaleway.com/vpc/v2/regions/fr-par/private-networks")
      .to_return(status: 201, body: {
        id: "net-456", name: "new-network", subnets: [{ subnet: "10.0.1.0/24" }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    network = @provider.find_or_create_network("new-network")

    assert_equal "net-456", network.id
  end

  # Firewall tests

  def test_find_or_create_firewall_returns_existing
    stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/security_groups")
      .to_return(status: 200, body: {
        security_groups: [{ id: "sg-123", name: "test-firewall" }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    firewall = @provider.find_or_create_firewall("test-firewall")

    assert_equal "sg-123", firewall.id
    assert_equal "test-firewall", firewall.name
  end

  # Server tests

  def test_find_server_returns_nil_when_not_found
    stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers")
      .to_return(status: 200, body: { servers: [] }.to_json, headers: { "Content-Type" => "application/json" })

    server = @provider.find_server("nonexistent")

    assert_nil server
  end

  def test_find_server_returns_server_when_found
    stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers")
      .to_return(status: 200, body: {
        servers: [{
          id: "srv-123",
          name: "test-server",
          state: "running",
          public_ip: { address: "1.2.3.4" }
        }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    server = @provider.find_server("test-server")

    assert_equal "srv-123", server.id
    assert_equal "test-server", server.name
    assert_equal "running", server.status
    assert_equal "1.2.3.4", server.public_ipv4
    # Scaleway private IP is discovered via SSH, not API
    assert_nil server.private_ipv4
  end

  def test_list_servers
    stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers")
      .to_return(status: 200, body: {
        servers: [
          { id: "s1", name: "srv-1", state: "running", public_ip: { address: "1.1.1.1" } },
          { id: "s2", name: "srv-2", state: "stopped", public_ip: nil }
        ]
      }.to_json, headers: { "Content-Type" => "application/json" })

    servers = @provider.list_servers

    assert_equal 2, servers.size
    assert_equal "srv-1", servers[0].name
    assert_equal "srv-2", servers[1].name
  end

  def test_server_ip
    stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers")
      .to_return(status: 200, body: {
        servers: [{
          id: "srv-123",
          name: "my-server",
          state: "running",
          public_ip: { address: "5.6.7.8" }
        }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    ip = @provider.server_ip("my-server")

    assert_equal "5.6.7.8", ip
  end

  # Volume tests

  def test_get_volume_by_name_returns_nil_when_not_found
    stub_request(:get, "https://api.scaleway.com/block/v1alpha1/zones/fr-par-1/volumes")
      .to_return(status: 200, body: { volumes: [] }.to_json, headers: { "Content-Type" => "application/json" })

    volume = @provider.get_volume_by_name("nonexistent")

    assert_nil volume
  end

  def test_get_volume_by_name_returns_volume
    stub_request(:get, "https://api.scaleway.com/block/v1alpha1/zones/fr-par-1/volumes")
      .to_return(status: 200, body: {
        volumes: [{
          id: "vol-123",
          name: "test-volume",
          size: 20_000_000_000,
          zone: "fr-par-1",
          status: "available"
        }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    volume = @provider.get_volume_by_name("test-volume")

    assert_equal "vol-123", volume.id
    assert_equal "test-volume", volume.name
    assert_equal 20, volume.size
    assert_equal "fr-par-1", volume.location
  end

  # Validation tests

  def test_validate_credentials_success
    stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/products/servers")
      .to_return(status: 200, body: { servers: {} }.to_json, headers: { "Content-Type" => "application/json" })

    assert @provider.validate_credentials
  end

  def test_validate_credentials_failure
    stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/products/servers")
      .to_return(status: 401, body: { message: "invalid token" }.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(Nvoi::Errors::ValidationError) do
      @provider.validate_credentials
    end
  end

  def test_validate_instance_type_success
    stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/products/servers")
      .to_return(status: 200, body: {
        servers: { "DEV1-S" => { name: "DEV1-S" } }
      }.to_json, headers: { "Content-Type" => "application/json" })

    assert @provider.validate_instance_type("DEV1-S")
  end

  def test_validate_instance_type_failure
    stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/products/servers")
      .to_return(status: 200, body: { servers: {} }.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(Nvoi::Errors::ValidationError) do
      @provider.validate_instance_type("invalid-type")
    end
  end

  def test_validate_region_success
    assert @provider.validate_region("fr-par-1")
    assert @provider.validate_region("nl-ams-2")
    assert @provider.validate_region("pl-waw-1")
  end

  def test_validate_region_failure
    assert_raises(Nvoi::Errors::ValidationError) do
      @provider.validate_region("invalid-zone")
    end
  end

  def test_valid_zones_constant
    assert_includes Nvoi::External::Cloud::Scaleway::VALID_ZONES, "fr-par-1"
    assert_includes Nvoi::External::Cloud::Scaleway::VALID_ZONES, "nl-ams-1"
    assert_includes Nvoi::External::Cloud::Scaleway::VALID_ZONES, "pl-waw-1"
  end

  # Error handling tests

  def test_handles_401_error
    stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers")
      .to_return(status: 401, body: { message: "unauthorized" }.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(Nvoi::Errors::AuthenticationError) do
      @provider.list_servers
    end
  end

  def test_handles_403_error
    stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers")
      .to_return(status: 403, body: { message: "forbidden" }.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(Nvoi::Errors::AuthenticationError) do
      @provider.list_servers
    end
  end

  def test_handles_429_rate_limit
    stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers")
      .to_return(status: 429, body: {}.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(Nvoi::Errors::RateLimitError) do
      @provider.list_servers
    end
  end

  def test_handles_409_conflict
    stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers")
      .to_return(status: 409, body: { message: "conflict" }.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(Nvoi::Errors::ConflictError) do
      @provider.list_servers
    end
  end

  def test_handles_api_error
    stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers")
      .to_return(status: 500, body: { message: "internal error" }.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(Nvoi::Errors::ApiError) do
      @provider.list_servers
    end
  end

  # Delete operations

  def test_delete_firewall
    stub_request(:delete, "https://api.scaleway.com/instance/v1/zones/fr-par-1/security_groups/sg-123")
      .to_return(status: 204)

    @provider.delete_firewall("sg-123")
  end

  def test_delete_volume
    stub_request(:delete, "https://api.scaleway.com/block/v1alpha1/zones/fr-par-1/volumes/vol-123")
      .to_return(status: 204)

    @provider.delete_volume("vol-123")
  end

  def test_get_volume
    stub_request(:get, "https://api.scaleway.com/block/v1alpha1/zones/fr-par-1/volumes/vol-555")
      .to_return(status: 200, body: {
        id: "vol-555",
        name: "my-volume",
        size: 50_000_000_000,
        zone: "fr-par-1",
        status: "available",
        references: [{ product_resource_type: "instance_server", product_resource_id: "srv-111" }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    volume = @provider.get_volume("vol-555")

    assert_equal "vol-555", volume.id
    assert_equal "my-volume", volume.name
    assert_equal 50, volume.size
    assert_equal "fr-par-1", volume.location
    assert_equal "srv-111", volume.server_id
  end

  def test_get_volume_returns_nil_on_not_found
    stub_request(:get, "https://api.scaleway.com/block/v1alpha1/zones/fr-par-1/volumes/vol-999")
      .to_return(status: 404, body: { message: "not found" }.to_json, headers: { "Content-Type" => "application/json" })

    volume = @provider.get_volume("vol-999")

    assert_nil volume
  end

  def test_get_network_by_name_raises_when_not_found
    stub_request(:get, "https://api.scaleway.com/vpc/v2/regions/fr-par/private-networks")
      .to_return(status: 200, body: { private_networks: [] }.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(Nvoi::Errors::NetworkError) do
      @provider.get_network_by_name("nonexistent")
    end
  end

  def test_get_network_by_name_success
    stub_request(:get, "https://api.scaleway.com/vpc/v2/regions/fr-par/private-networks")
      .to_return(status: 200, body: {
        private_networks: [{ id: "net-100", name: "my-net", subnets: [{ subnet: "10.0.0.0/8" }] }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    network = @provider.get_network_by_name("my-net")

    assert_equal "net-100", network.id
    assert_equal "my-net", network.name
  end

  def test_get_firewall_by_name_raises_when_not_found
    stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/security_groups")
      .to_return(status: 200, body: { security_groups: [] }.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(Nvoi::Errors::FirewallError) do
      @provider.get_firewall_by_name("nonexistent")
    end
  end

  def test_get_firewall_by_name_success
    stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/security_groups")
      .to_return(status: 200, body: {
        security_groups: [{ id: "sg-200", name: "my-sg" }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    firewall = @provider.get_firewall_by_name("my-sg")

    assert_equal "sg-200", firewall.id
    assert_equal "my-sg", firewall.name
  end

  def test_server_ip_returns_nil_when_not_found
    stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers")
      .to_return(status: 200, body: { servers: [] }.to_json, headers: { "Content-Type" => "application/json" })

    ip = @provider.server_ip("nonexistent")

    assert_nil ip
  end

  # Create operations

  def test_find_or_create_firewall_creates_new
    stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/security_groups")
      .to_return(status: 200, body: { security_groups: [] }.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:post, "https://api.scaleway.com/instance/v1/zones/fr-par-1/security_groups")
      .to_return(status: 201, body: {
        security_group: { id: "sg-new", name: "new-firewall" }
      }.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:post, "https://api.scaleway.com/instance/v1/zones/fr-par-1/security_groups/sg-new/rules")
      .to_return(status: 201, body: {}.to_json, headers: { "Content-Type" => "application/json" })

    firewall = @provider.find_or_create_firewall("new-firewall")

    assert_equal "sg-new", firewall.id
    assert_equal "new-firewall", firewall.name
  end

  def test_create_server
    # Stub list_server_types
    stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/products/servers")
      .to_return(status: 200, body: {
        servers: { "DEV1-S" => { name: "DEV1-S" } }
      }.to_json, headers: { "Content-Type" => "application/json" })

    # Stub list_images (find_image) - first tries instance images
    stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/images?arch=x86_64&name=Ubuntu%2022.04")
      .to_return(status: 200, body: {
        images: [{ id: "img-123", name: "Ubuntu 22.04" }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    # Stub create server
    stub_request(:post, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers")
      .to_return(status: 201, body: {
        server: {
          id: "srv-new",
          name: "new-server",
          state: "stopped",
          public_ip: nil
        }
      }.to_json, headers: { "Content-Type" => "application/json" })

    # Stub poweron action
    stub_request(:post, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers/srv-new/action")
      .to_return(status: 202, body: {}.to_json, headers: { "Content-Type" => "application/json" })

    # Stub get_server_api (final fetch)
    stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers/srv-new")
      .to_return(status: 200, body: {
        server: {
          id: "srv-new",
          name: "new-server",
          state: "running",
          public_ip: { address: "1.2.3.4" }
        }
      }.to_json, headers: { "Content-Type" => "application/json" })

    opts = Nvoi::External::Cloud::Types::Server::CreateOptions.new(
      name: "new-server",
      type: "DEV1-S",
      image: "Ubuntu 22.04",
      location: "fr-par-1"
    )
    server = @provider.create_server(opts)

    assert_equal "srv-new", server.id
    assert_equal "new-server", server.name
  end

  def test_create_volume
    # Stub get_server_api
    stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers/srv-123")
      .to_return(status: 200, body: {
        server: {
          id: "srv-123",
          name: "test-server",
          state: "running",
          public_ip: { address: "1.2.3.4" }
        }
      }.to_json, headers: { "Content-Type" => "application/json" })

    # Stub create volume
    stub_request(:post, "https://api.scaleway.com/block/v1alpha1/zones/fr-par-1/volumes")
      .to_return(status: 201, body: {
        id: "vol-new",
        name: "new-volume",
        size: 50_000_000_000,
        zone: "fr-par-1",
        status: "creating"
      }.to_json, headers: { "Content-Type" => "application/json" })

    opts = Nvoi::External::Cloud::Types::Volume::CreateOptions.new(
      name: "new-volume",
      size: 50,
      server_id: "srv-123"
    )
    volume = @provider.create_volume(opts)

    assert_equal "vol-new", volume.id
    assert_equal "new-volume", volume.name
    assert_equal 50, volume.size
  end

  def test_wait_for_server_success
    stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers/srv-123")
      .to_return(status: 200, body: {
        server: {
          id: "srv-123",
          name: "test",
          state: "running",
          public_ip: { address: "1.2.3.4" }
        }
      }.to_json, headers: { "Content-Type" => "application/json" })

    server = @provider.wait_for_server("srv-123", 1)

    assert_equal "running", server.status
    assert_equal "1.2.3.4", server.public_ipv4
  end

  def test_delete_server
    # Stub list private nics
    stub_request(:get, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers/srv-123/private_nics")
      .to_return(status: 200, body: { private_nics: [] }.to_json, headers: { "Content-Type" => "application/json" })

    # Stub terminate action
    stub_request(:post, "https://api.scaleway.com/instance/v1/zones/fr-par-1/servers/srv-123/action")
      .to_return(status: 202, body: {}.to_json, headers: { "Content-Type" => "application/json" })

    @provider.delete_server("srv-123")
  end
end
