# frozen_string_literal: true

require "test_helper"
require "webmock/minitest"

class Nvoi::Providers::ScalewayTest < Minitest::Test
  def setup
    @secret_key = "test-secret-key"
    @project_id = "test-project-id"
    @zone = "fr-par-1"
    @region = "fr-par"
    @provider = Nvoi::Providers::Scaleway.new(@secret_key, @project_id, zone: @zone)

    @instance_base = "https://api.scaleway.com/instance/v1/zones/#{@zone}"
    @vpc_base = "https://api.scaleway.com/vpc/v2/regions/#{@region}"
    @block_base = "https://api.scaleway.com/block/v1alpha1/zones/#{@zone}"
    @json_headers = { "Content-Type" => "application/json" }
  end

  def json_response(body = nil, status: 200, **kwargs)
    body = kwargs if body.nil? && kwargs.any?
    { status:, body: body.to_json, headers: @json_headers }
  end

  # Validation tests

  def test_validate_instance_type_valid
    stub_request(:get, "#{@instance_base}/products/servers")
      .to_return(json_response(servers: {
        "DEV1-S" => { ncpus: 2, ram: 2_147_483_648 },
        "DEV1-M" => { ncpus: 3, ram: 4_294_967_296 }
      }))

    assert @provider.validate_instance_type("DEV1-S")
  end

  def test_validate_instance_type_invalid
    stub_request(:get, "#{@instance_base}/products/servers")
      .to_return(json_response(servers: {
        "DEV1-S" => { ncpus: 2, ram: 2_147_483_648 }
      }))

    error = assert_raises(Nvoi::ValidationError) do
      @provider.validate_instance_type("INVALID-TYPE")
    end
    assert_match(/invalid scaleway server type/, error.message)
  end

  def test_validate_region_valid
    assert @provider.validate_region("fr-par-1")
    assert @provider.validate_region("nl-ams-2")
    assert @provider.validate_region("pl-waw-3")
  end

  def test_validate_region_invalid
    error = assert_raises(Nvoi::ValidationError) do
      @provider.validate_region("invalid-zone")
    end
    assert_match(/invalid scaleway zone/, error.message)
  end

  def test_validate_credentials_valid
    stub_request(:get, "#{@instance_base}/products/servers")
      .to_return(json_response(servers: {}))

    assert @provider.validate_credentials
  end

  def test_validate_credentials_invalid
    stub_request(:get, "#{@instance_base}/products/servers")
      .to_return(json_response({ message: "unauthorized" }, status: 401))

    error = assert_raises(Nvoi::ValidationError) do
      @provider.validate_credentials
    end
    assert_match(/credentials invalid/, error.message)
  end

  # Network operations

  def test_find_or_create_network_creates_when_not_found
    stub_request(:get, "#{@vpc_base}/private-networks")
      .to_return(json_response(private_networks: []))

    stub_request(:post, "#{@vpc_base}/private-networks")
      .to_return(json_response({
        id: "pn-123",
        name: "test-network",
        subnets: [{ subnet: "10.0.1.0/24" }]
      }, status: 201))

    network = @provider.find_or_create_network("test-network")

    assert_equal "pn-123", network.id
    assert_equal "test-network", network.name
  end

  def test_find_or_create_network_finds_existing
    stub_request(:get, "#{@vpc_base}/private-networks")
      .to_return(json_response(private_networks: [
        { id: "pn-456", name: "existing-network", subnets: [{ subnet: "10.0.1.0/24" }] }
      ]))

    network = @provider.find_or_create_network("existing-network")

    assert_equal "pn-456", network.id
    assert_equal "existing-network", network.name
  end

  def test_get_network_by_name_raises_when_not_found
    stub_request(:get, "#{@vpc_base}/private-networks")
      .to_return(json_response(private_networks: []))

    error = assert_raises(Nvoi::NetworkError) do
      @provider.get_network_by_name("nonexistent")
    end
    assert_match(/network not found/, error.message)
  end

  # Firewall operations (Security Groups)

  def test_find_or_create_firewall_creates_when_not_found
    stub_request(:get, "#{@instance_base}/security_groups")
      .to_return(json_response(security_groups: []))

    stub_request(:post, "#{@instance_base}/security_groups")
      .to_return(json_response({
        security_group: { id: "sg-789", name: "test-firewall" }
      }, status: 201))

    stub_request(:post, "#{@instance_base}/security_groups/sg-789/rules")
      .to_return(json_response({ rule: { id: "rule-1" } }, status: 201))

    firewall = @provider.find_or_create_firewall("test-firewall")

    assert_equal "sg-789", firewall.id
    assert_equal "test-firewall", firewall.name
  end

  def test_find_or_create_firewall_finds_existing
    stub_request(:get, "#{@instance_base}/security_groups")
      .to_return(json_response(security_groups: [
        { id: "sg-101", name: "existing-fw" }
      ]))

    firewall = @provider.find_or_create_firewall("existing-fw")

    assert_equal "sg-101", firewall.id
  end

  def test_get_firewall_by_name_raises_when_not_found
    stub_request(:get, "#{@instance_base}/security_groups")
      .to_return(json_response(security_groups: []))

    error = assert_raises(Nvoi::FirewallError) do
      @provider.get_firewall_by_name("nonexistent")
    end
    assert_match(/security group not found/, error.message)
  end

  # Server operations

  def test_find_server_returns_nil_when_not_found
    stub_request(:get, "#{@instance_base}/servers")
      .to_return(json_response(servers: []))

    server = @provider.find_server("nonexistent")
    assert_nil server
  end

  def test_find_server_returns_server_when_found
    stub_request(:get, "#{@instance_base}/servers")
      .to_return(json_response(servers: [
        {
          id: "srv-111",
          name: "my-server",
          state: "running",
          public_ip: { address: "1.2.3.4" }
        }
      ]))

    server = @provider.find_server("my-server")

    refute_nil server
    assert_equal "srv-111", server.id
    assert_equal "1.2.3.4", server.public_ipv4
    assert_equal "running", server.status
  end

  def test_list_servers
    stub_request(:get, "#{@instance_base}/servers")
      .to_return(json_response(servers: [
        { id: "srv-1", name: "server-1", state: "running", public_ip: { address: "1.1.1.1" } },
        { id: "srv-2", name: "server-2", state: "running", public_ip: { address: "2.2.2.2" } }
      ]))

    servers = @provider.list_servers
    assert_equal 2, servers.length
  end

  def test_create_server
    stub_request(:get, "#{@instance_base}/products/servers")
      .to_return(json_response(servers: { "DEV1-S" => { ncpus: 2 } }))

    stub_request(:get, "#{@instance_base}/images?arch=x86_64&name=ubuntu_jammy")
      .to_return(json_response(images: [{ id: "img-123", name: "ubuntu_jammy" }]))

    stub_request(:post, "#{@instance_base}/servers")
      .to_return(json_response({
        server: {
          id: "srv-999",
          name: "new-server",
          state: "stopped",
          public_ip: nil
        }
      }, status: 201))

    stub_request(:post, "#{@instance_base}/servers/srv-999/action")
      .to_return(json_response({ task: { id: "task-1" } }))

    stub_request(:get, "#{@instance_base}/servers/srv-999")
      .to_return(json_response({
        server: {
          id: "srv-999",
          name: "new-server",
          state: "running",
          public_ip: { address: "5.6.7.8" }
        }
      }))

    opts = Nvoi::Providers::ServerCreateOptions.new(
      name: "new-server",
      type: "DEV1-S",
      image: "ubuntu-22.04",
      location: "fr-par-1",
      user_data: nil,
      network_id: nil,
      firewall_id: nil
    )

    server = @provider.create_server(opts)

    assert_equal "srv-999", server.id
    assert_equal "new-server", server.name
  end

  def test_wait_for_server_success
    stub_request(:get, "#{@instance_base}/servers/srv-123")
      .to_return(json_response({
        server: {
          id: "srv-123",
          name: "test",
          state: "running",
          public_ip: { address: "1.2.3.4" }
        }
      }))

    server = @provider.wait_for_server("srv-123", 1)
    assert_equal "running", server.status
  end

  def test_wait_for_server_timeout
    stub_request(:get, "#{@instance_base}/servers/srv-123")
      .to_return(json_response({
        server: {
          id: "srv-123",
          name: "test",
          state: "starting",
          public_ip: nil
        }
      }))

    error = assert_raises(Nvoi::ServerCreationError) do
      @provider.wait_for_server("srv-123", 1)
    end
    assert_match(/did not become running/, error.message)
  end

  # Volume operations

  def test_get_volume_by_name_returns_nil_when_not_found
    stub_request(:get, "#{@block_base}/volumes")
      .to_return(json_response(volumes: []))

    volume = @provider.get_volume_by_name("nonexistent")
    assert_nil volume
  end

  def test_get_volume_by_name_returns_volume_when_found
    stub_request(:get, "#{@block_base}/volumes")
      .to_return(json_response(volumes: [
        {
          id: "vol-222",
          name: "test-volume",
          size: 20_000_000_000,
          zone: "fr-par-1",
          status: "available",
          references: []
        }
      ]))

    volume = @provider.get_volume_by_name("test-volume")

    refute_nil volume
    assert_equal "vol-222", volume.id
    assert_equal 20, volume.size
  end

  def test_create_volume
    stub_request(:get, "#{@instance_base}/servers/srv-123")
      .to_return(json_response({
        server: {
          id: "srv-123",
          name: "test",
          state: "running",
          zone: "fr-par-1"
        }
      }))

    stub_request(:post, "#{@block_base}/volumes")
      .to_return(json_response({
        id: "vol-new",
        name: "new-volume",
        size: 10_000_000_000,
        zone: "fr-par-1",
        status: "creating",
        references: []
      }, status: 201))

    opts = Nvoi::Providers::VolumeCreateOptions.new(
      name: "new-volume",
      size: 10,
      server_id: "srv-123"
    )

    volume = @provider.create_volume(opts)

    assert_equal "vol-new", volume.id
    assert_equal "new-volume", volume.name
  end

  # API error handling

  def test_api_error_401
    stub_request(:get, "#{@instance_base}/servers")
      .to_return(json_response({ message: "unauthorized" }, status: 401))

    error = assert_raises(Nvoi::AuthenticationError) do
      @provider.list_servers
    end
    assert_match(/Invalid Scaleway API token/, error.message)
  end

  def test_api_error_404
    stub_request(:get, "#{@instance_base}/servers/nonexistent")
      .to_return(json_response({ message: "server not found" }, status: 404))

    error = assert_raises(Nvoi::NotFoundError) do
      @provider.wait_for_server("nonexistent", 1)
    end
    assert_match(/server not found/, error.message)
  end

  def test_api_error_429
    stub_request(:get, "#{@instance_base}/servers")
      .to_return(json_response({ message: "rate limited" }, status: 429))

    error = assert_raises(Nvoi::RateLimitError) do
      @provider.list_servers
    end
    assert_match(/Rate limited/, error.message)
  end

  # Image mapping

  def test_image_name_mapping
    stub_request(:get, "#{@instance_base}/products/servers")
      .to_return(json_response(servers: { "DEV1-S" => {} }))

    # Test ubuntu-24.04 maps to ubuntu_noble
    stub_request(:get, "#{@instance_base}/images?arch=x86_64&name=ubuntu_noble")
      .to_return(json_response(images: [{ id: "img-noble", name: "ubuntu_noble" }]))

    stub_request(:post, "#{@instance_base}/servers")
      .to_return(json_response({
        server: { id: "srv-1", name: "test", state: "stopped" }
      }, status: 201))

    stub_request(:post, "#{@instance_base}/servers/srv-1/action")
      .to_return(json_response({ task: { id: "task-1" } }))

    stub_request(:get, "#{@instance_base}/servers/srv-1")
      .to_return(json_response({
        server: { id: "srv-1", name: "test", state: "running", public_ip: { address: "1.1.1.1" } }
      }))

    opts = Nvoi::Providers::ServerCreateOptions.new(
      name: "test",
      type: "DEV1-S",
      image: "ubuntu-24.04",
      location: "fr-par-1"
    )

    server = @provider.create_server(opts)
    assert_equal "srv-1", server.id
  end
end
