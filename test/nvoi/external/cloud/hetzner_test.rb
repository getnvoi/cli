# frozen_string_literal: true

require "test_helper"
require "webmock/minitest"

class HetznerCloudTest < Minitest::Test
  def setup
    WebMock.disable_net_connect!
    @provider = Nvoi::External::Cloud::Hetzner.new("test-token")
  end

  def teardown
    WebMock.reset!
  end

  # Network tests

  def test_find_or_create_network_returns_existing
    stub_request(:get, "https://api.hetzner.cloud/v1/networks")
      .to_return(status: 200, body: {
        networks: [{ id: 123, name: "test-network", ip_range: "10.0.0.0/16" }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    network = @provider.find_or_create_network("test-network")

    assert_equal "123", network.id
    assert_equal "test-network", network.name
    assert_equal "10.0.0.0/16", network.ip_range
  end

  def test_find_or_create_network_creates_new
    stub_request(:get, "https://api.hetzner.cloud/v1/networks")
      .to_return(status: 200, body: { networks: [] }.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:post, "https://api.hetzner.cloud/v1/networks")
      .to_return(status: 201, body: {
        network: { id: 456, name: "new-network", ip_range: "10.0.0.0/16" }
      }.to_json, headers: { "Content-Type" => "application/json" })

    network = @provider.find_or_create_network("new-network")

    assert_equal "456", network.id
    assert_equal "new-network", network.name
  end

  def test_get_network_by_name_raises_when_not_found
    stub_request(:get, "https://api.hetzner.cloud/v1/networks")
      .to_return(status: 200, body: { networks: [] }.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(Nvoi::Errors::NetworkError) do
      @provider.get_network_by_name("nonexistent")
    end
  end

  # Firewall tests

  def test_find_or_create_firewall_returns_existing
    stub_request(:get, "https://api.hetzner.cloud/v1/firewalls")
      .to_return(status: 200, body: {
        firewalls: [{ id: 789, name: "test-firewall" }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    firewall = @provider.find_or_create_firewall("test-firewall")

    assert_equal "789", firewall.id
    assert_equal "test-firewall", firewall.name
  end

  def test_find_or_create_firewall_creates_new
    stub_request(:get, "https://api.hetzner.cloud/v1/firewalls")
      .to_return(status: 200, body: { firewalls: [] }.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:post, "https://api.hetzner.cloud/v1/firewalls")
      .to_return(status: 201, body: {
        firewall: { id: 101, name: "new-firewall" }
      }.to_json, headers: { "Content-Type" => "application/json" })

    firewall = @provider.find_or_create_firewall("new-firewall")

    assert_equal "101", firewall.id
    assert_equal "new-firewall", firewall.name
  end

  # Server tests

  def test_find_server_returns_nil_when_not_found
    stub_request(:get, "https://api.hetzner.cloud/v1/servers")
      .to_return(status: 200, body: { servers: [] }.to_json, headers: { "Content-Type" => "application/json" })

    server = @provider.find_server("nonexistent")

    assert_nil server
  end

  def test_find_server_returns_server_when_found
    stub_request(:get, "https://api.hetzner.cloud/v1/servers")
      .to_return(status: 200, body: {
        servers: [{
          id: 111,
          name: "test-server",
          status: "running",
          public_net: { ipv4: { ip: "1.2.3.4" } }
        }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    server = @provider.find_server("test-server")

    assert_equal "111", server.id
    assert_equal "test-server", server.name
    assert_equal "running", server.status
    assert_equal "1.2.3.4", server.public_ipv4
  end

  def test_list_servers
    stub_request(:get, "https://api.hetzner.cloud/v1/servers")
      .to_return(status: 200, body: {
        servers: [
          { id: 1, name: "srv-1", status: "running", public_net: { ipv4: { ip: "1.1.1.1" } } },
          { id: 2, name: "srv-2", status: "stopped", public_net: { ipv4: { ip: "2.2.2.2" } } }
        ]
      }.to_json, headers: { "Content-Type" => "application/json" })

    servers = @provider.list_servers

    assert_equal 2, servers.size
    assert_equal "srv-1", servers[0].name
    assert_equal "srv-2", servers[1].name
  end

  # Volume tests

  def test_get_volume_by_name_returns_nil_when_not_found
    stub_request(:get, "https://api.hetzner.cloud/v1/volumes")
      .to_return(status: 200, body: { volumes: [] }.to_json, headers: { "Content-Type" => "application/json" })

    volume = @provider.get_volume_by_name("nonexistent")

    assert_nil volume
  end

  def test_get_volume_by_name_returns_volume
    stub_request(:get, "https://api.hetzner.cloud/v1/volumes")
      .to_return(status: 200, body: {
        volumes: [{
          id: 222,
          name: "test-volume",
          size: 20,
          location: { name: "fsn1" },
          status: "available",
          server: nil,
          linux_device: "/dev/sdb"
        }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    volume = @provider.get_volume_by_name("test-volume")

    assert_equal "222", volume.id
    assert_equal "test-volume", volume.name
    assert_equal 20, volume.size
    assert_equal "fsn1", volume.location
  end

  # Validation tests

  def test_validate_credentials_success
    stub_request(:get, "https://api.hetzner.cloud/v1/server_types")
      .to_return(status: 200, body: { server_types: [] }.to_json, headers: { "Content-Type" => "application/json" })

    assert @provider.validate_credentials
  end

  def test_validate_credentials_failure
    stub_request(:get, "https://api.hetzner.cloud/v1/server_types")
      .to_return(status: 401, body: { error: { message: "invalid token" } }.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(Nvoi::Errors::ValidationError) do
      @provider.validate_credentials
    end
  end

  def test_validate_instance_type_success
    stub_request(:get, "https://api.hetzner.cloud/v1/server_types")
      .to_return(status: 200, body: {
        server_types: [{ name: "cpx11" }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    assert @provider.validate_instance_type("cpx11")
  end

  def test_validate_instance_type_failure
    stub_request(:get, "https://api.hetzner.cloud/v1/server_types")
      .to_return(status: 200, body: { server_types: [] }.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(Nvoi::Errors::ValidationError) do
      @provider.validate_instance_type("invalid-type")
    end
  end

  def test_validate_region_success
    stub_request(:get, "https://api.hetzner.cloud/v1/locations")
      .to_return(status: 200, body: {
        locations: [{ name: "fsn1" }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    assert @provider.validate_region("fsn1")
  end

  def test_validate_region_failure
    stub_request(:get, "https://api.hetzner.cloud/v1/locations")
      .to_return(status: 200, body: { locations: [] }.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(Nvoi::Errors::ValidationError) do
      @provider.validate_region("invalid-location")
    end
  end

  # Error handling tests

  def test_handles_404_error
    stub_request(:get, "https://api.hetzner.cloud/v1/volumes/999")
      .to_return(status: 404, body: { error: { message: "not found" } }.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(Nvoi::Errors::NotFoundError) do
      @provider.get_volume(999)
    end
  end

  def test_handles_422_validation_error
    stub_request(:post, "https://api.hetzner.cloud/v1/networks")
      .to_return(status: 422, body: { error: { message: "invalid data" } }.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:get, "https://api.hetzner.cloud/v1/networks")
      .to_return(status: 200, body: { networks: [] }.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(Nvoi::Errors::ValidationError) do
      @provider.find_or_create_network("test")
    end
  end

  def test_handles_api_error
    stub_request(:get, "https://api.hetzner.cloud/v1/servers")
      .to_return(status: 500, body: { error: { message: "internal error" } }.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(Nvoi::Errors::ApiError) do
      @provider.list_servers
    end
  end

  # Delete operations

  def test_delete_network
    stub_request(:delete, "https://api.hetzner.cloud/v1/networks/123")
      .to_return(status: 204)

    @provider.delete_network("123")
  end

  def test_delete_firewall
    stub_request(:delete, "https://api.hetzner.cloud/v1/firewalls/456")
      .to_return(status: 204)

    @provider.delete_firewall("456")
  end

  def test_delete_volume
    stub_request(:delete, "https://api.hetzner.cloud/v1/volumes/789")
      .to_return(status: 204)

    @provider.delete_volume("789")
  end

  def test_attach_volume
    stub_request(:post, "https://api.hetzner.cloud/v1/volumes/100/actions/attach")
      .to_return(status: 200, body: { action: { id: 1 } }.to_json, headers: { "Content-Type" => "application/json" })

    @provider.attach_volume("100", "200")
  end

  def test_detach_volume
    stub_request(:post, "https://api.hetzner.cloud/v1/volumes/100/actions/detach")
      .to_return(status: 200, body: { action: { id: 1 } }.to_json, headers: { "Content-Type" => "application/json" })

    @provider.detach_volume("100")
  end

  def test_get_volume
    stub_request(:get, "https://api.hetzner.cloud/v1/volumes/555")
      .to_return(status: 200, body: {
        volume: {
          id: 555,
          name: "my-volume",
          size: 50,
          location: { name: "nbg1" },
          status: "available",
          server: 111,
          linux_device: "/dev/sdc"
        }
      }.to_json, headers: { "Content-Type" => "application/json" })

    volume = @provider.get_volume("555")

    assert_equal "555", volume.id
    assert_equal "my-volume", volume.name
    assert_equal 50, volume.size
    assert_equal "nbg1", volume.location
    assert_equal "111", volume.server_id
    assert_equal "/dev/sdc", volume.device_path
  end

  def test_get_network_by_name_success
    stub_request(:get, "https://api.hetzner.cloud/v1/networks")
      .to_return(status: 200, body: {
        networks: [{ id: 100, name: "my-net", ip_range: "10.0.0.0/8" }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    network = @provider.get_network_by_name("my-net")

    assert_equal "100", network.id
    assert_equal "my-net", network.name
  end

  def test_get_firewall_by_name_raises_when_not_found
    stub_request(:get, "https://api.hetzner.cloud/v1/firewalls")
      .to_return(status: 200, body: { firewalls: [] }.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(Nvoi::Errors::FirewallError) do
      @provider.get_firewall_by_name("nonexistent")
    end
  end

  def test_get_firewall_by_name_success
    stub_request(:get, "https://api.hetzner.cloud/v1/firewalls")
      .to_return(status: 200, body: {
        firewalls: [{ id: 200, name: "my-fw" }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    firewall = @provider.get_firewall_by_name("my-fw")

    assert_equal "200", firewall.id
    assert_equal "my-fw", firewall.name
  end

  # Create operations

  def test_create_server
    stub_request(:get, "https://api.hetzner.cloud/v1/server_types")
      .to_return(status: 200, body: {
        server_types: [{ id: 1, name: "cpx11" }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:get, "https://api.hetzner.cloud/v1/images?name=ubuntu-22.04")
      .to_return(status: 200, body: {
        images: [{ id: 100, name: "ubuntu-22.04" }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:get, "https://api.hetzner.cloud/v1/locations")
      .to_return(status: 200, body: {
        locations: [{ id: 1, name: "fsn1" }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:post, "https://api.hetzner.cloud/v1/servers")
      .to_return(status: 201, body: {
        server: {
          id: 999,
          name: "new-server",
          status: "initializing",
          public_net: { ipv4: { ip: nil } }
        }
      }.to_json, headers: { "Content-Type" => "application/json" })

    opts = Nvoi::Objects::Server::CreateOptions.new(
      name: "new-server",
      type: "cpx11",
      image: "ubuntu-22.04",
      location: "fsn1"
    )
    server = @provider.create_server(opts)

    assert_equal "999", server.id
    assert_equal "new-server", server.name
  end

  def test_create_volume
    stub_request(:get, "https://api.hetzner.cloud/v1/servers/123")
      .to_return(status: 200, body: {
        server: {
          id: 123,
          name: "srv",
          status: "running",
          datacenter: { location: { name: "fsn1" } },
          public_net: { ipv4: { ip: "1.2.3.4" } }
        }
      }.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:post, "https://api.hetzner.cloud/v1/volumes")
      .to_return(status: 201, body: {
        volume: {
          id: 888,
          name: "new-vol",
          size: 50,
          location: { name: "fsn1" },
          status: "creating",
          server: nil
        }
      }.to_json, headers: { "Content-Type" => "application/json" })

    opts = Nvoi::Objects::Volume::CreateOptions.new(
      name: "new-vol",
      size: 50,
      server_id: "123"
    )
    volume = @provider.create_volume(opts)

    assert_equal "888", volume.id
    assert_equal "new-vol", volume.name
    assert_equal 50, volume.size
  end

  def test_wait_for_server_success
    stub_request(:get, "https://api.hetzner.cloud/v1/servers/123")
      .to_return(status: 200, body: {
        server: {
          id: 123,
          name: "srv",
          status: "running",
          public_net: { ipv4: { ip: "1.2.3.4" } }
        }
      }.to_json, headers: { "Content-Type" => "application/json" })

    server = @provider.wait_for_server("123", 1)

    assert_equal "running", server.status
    assert_equal "1.2.3.4", server.public_ipv4
  end

  def test_handles_401_error
    stub_request(:get, "https://api.hetzner.cloud/v1/servers")
      .to_return(status: 401, body: { error: { message: "unauthorized" } }.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(Nvoi::Errors::AuthenticationError) do
      @provider.list_servers
    end
  end
end
