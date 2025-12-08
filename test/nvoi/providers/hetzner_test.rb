# frozen_string_literal: true

require "test_helper"
require "webmock/minitest"

ServerOpts = Struct.new(:name, :type, :image, :location, :user_data, :network_id, :firewall_id, keyword_init: true)

class Nvoi::Providers::HetznerTest < Minitest::Test
  def setup
    @token = "test-api-token"
    @provider = Nvoi::Providers::Hetzner.new(@token)
    @base_url = "https://api.hetzner.cloud/v1"
    @json_headers = { "Content-Type" => "application/json" }
  end

  def json_response(body = nil, status: 200, **kwargs)
    body = kwargs if body.nil? && kwargs.any?
    { status:, body: body.to_json, headers: @json_headers }
  end

  # Validation tests

  def test_validate_instance_type_valid
    stub_request(:get, "#{@base_url}/server_types")
      .to_return(json_response(server_types: [
        { id: 1, name: "cx22", cores: 2, memory: 4, disk: 40 },
        { id: 2, name: "cx32", cores: 4, memory: 8, disk: 80 }
      ]))

    assert @provider.validate_instance_type("cx22")
  end

  def test_validate_instance_type_invalid
    stub_request(:get, "#{@base_url}/server_types")
      .to_return(json_response(server_types: [
        { id: 1, name: "cx22", cores: 2, memory: 4, disk: 40 }
      ]))

    error = assert_raises(Nvoi::ValidationError) do
      @provider.validate_instance_type("invalid-type")
    end
    assert_match(/invalid hetzner server type/, error.message)
  end

  def test_validate_region_valid
    stub_request(:get, "#{@base_url}/locations")
      .to_return(json_response(locations: [
        { id: 1, name: "fsn1", country: "DE", city: "Falkenstein" },
        { id: 2, name: "nbg1", country: "DE", city: "Nuremberg" }
      ]))

    assert @provider.validate_region("fsn1")
  end

  def test_validate_region_invalid
    stub_request(:get, "#{@base_url}/locations")
      .to_return(json_response(locations: [
        { id: 1, name: "fsn1", country: "DE", city: "Falkenstein" }
      ]))

    error = assert_raises(Nvoi::ValidationError) do
      @provider.validate_region("invalid-region")
    end
    assert_match(/invalid hetzner location/, error.message)
  end

  def test_validate_credentials_valid
    stub_request(:get, "#{@base_url}/server_types")
      .to_return(json_response(server_types: []))

    assert @provider.validate_credentials
  end

  def test_validate_credentials_invalid
    stub_request(:get, "#{@base_url}/server_types")
      .to_return(json_response({ error: { message: "unauthorized" } }, status: 401))

    error = assert_raises(Nvoi::ValidationError) do
      @provider.validate_credentials
    end
    assert_match(/credentials invalid/, error.message)
  end

  # Network operations

  def test_find_or_create_network_creates_when_not_found
    stub_request(:get, "#{@base_url}/networks")
      .to_return(json_response(networks: []))

    stub_request(:post, "#{@base_url}/networks")
      .to_return(json_response({ network: { id: 123, name: "test-network", ip_range: "10.0.0.0/16" } }, status: 201))

    network = @provider.find_or_create_network("test-network")

    assert_equal "123", network.id
    assert_equal "test-network", network.name
  end

  def test_find_or_create_network_finds_existing
    stub_request(:get, "#{@base_url}/networks")
      .to_return(json_response(networks: [
        { id: 456, name: "existing-network", ip_range: "10.0.0.0/16" }
      ]))

    network = @provider.find_or_create_network("existing-network")

    assert_equal "456", network.id
    assert_equal "existing-network", network.name
  end

  # Firewall operations

  def test_find_or_create_firewall_creates_when_not_found
    stub_request(:get, "#{@base_url}/firewalls")
      .to_return(json_response(firewalls: []))

    stub_request(:post, "#{@base_url}/firewalls")
      .to_return(json_response({ firewall: { id: 789, name: "test-firewall", rules: [] } }, status: 201))

    firewall = @provider.find_or_create_firewall("test-firewall")

    assert_equal "789", firewall.id
    assert_equal "test-firewall", firewall.name
  end

  def test_find_or_create_firewall_finds_existing
    stub_request(:get, "#{@base_url}/firewalls")
      .to_return(json_response(firewalls: [
        { id: 101, name: "existing-fw", rules: [] }
      ]))

    firewall = @provider.find_or_create_firewall("existing-fw")

    assert_equal "101", firewall.id
  end

  # Server operations

  def test_find_server_returns_nil_when_not_found
    stub_request(:get, "#{@base_url}/servers")
      .to_return(json_response(servers: []))

    server = @provider.find_server("nonexistent")
    assert_nil server
  end

  def test_find_server_returns_server_when_found
    stub_request(:get, "#{@base_url}/servers")
      .to_return(json_response(servers: [
        {
          id: 111,
          name: "my-server",
          status: "running",
          public_net: {
            ipv4: { ip: "1.2.3.4" },
            ipv6: { ip: "2001:db8::1" }
          }
        }
      ]))

    server = @provider.find_server("my-server")

    refute_nil server
    assert_equal "111", server.id
    assert_equal "1.2.3.4", server.public_ipv4
  end

  def test_list_servers
    stub_request(:get, "#{@base_url}/servers")
      .to_return(json_response(servers: [
        { id: 1, name: "server-1", status: "running", public_net: { ipv4: { ip: "1.1.1.1" } } },
        { id: 2, name: "server-2", status: "running", public_net: { ipv4: { ip: "2.2.2.2" } } }
      ]))

    servers = @provider.list_servers
    assert_equal 2, servers.length
  end

  def test_create_server
    stub_request(:get, "#{@base_url}/server_types")
      .to_return(json_response(server_types: [{ id: 1, name: "cx22" }]))

    stub_request(:get, "#{@base_url}/images?name=ubuntu-22.04")
      .to_return(json_response(images: [{ id: 1, name: "ubuntu-22.04" }]))

    stub_request(:get, "#{@base_url}/locations")
      .to_return(json_response(locations: [{ id: 1, name: "fsn1" }]))

    stub_request(:post, "#{@base_url}/servers")
      .to_return(json_response({
        server: {
          id: 999,
          name: "new-server",
          status: "initializing",
          public_net: { ipv4: { ip: "5.6.7.8" } }
        }
      }, status: 201))

    opts = ServerOpts.new(
      name: "new-server",
      type: "cx22",
      image: "ubuntu-22.04",
      location: "fsn1",
      user_data: "#!/bin/bash",
      network_id: nil,
      firewall_id: nil
    )

    server = @provider.create_server(opts)

    assert_equal "999", server.id
    assert_equal "new-server", server.name
  end

  def test_wait_for_server_success
    stub_request(:get, "#{@base_url}/servers/123")
      .to_return(json_response(server: { id: 123, name: "test", status: "running", public_net: { ipv4: { ip: "1.2.3.4" } } }))

    server = @provider.wait_for_server("123", 1)
    assert_equal "running", server.status
  end

  # Volume operations

  def test_get_volume_by_name_returns_nil_when_not_found
    stub_request(:get, "#{@base_url}/volumes")
      .to_return(json_response(volumes: []))

    volume = @provider.get_volume_by_name("nonexistent")
    assert_nil volume
  end

  def test_get_volume_by_name_returns_volume_when_found
    stub_request(:get, "#{@base_url}/volumes")
      .to_return(json_response(volumes: [
        {
          id: 222,
          name: "test-volume",
          size: 20,
          location: { name: "fsn1" },
          status: "available",
          server: nil,
          linux_device: "/dev/sdb"
        }
      ]))

    volume = @provider.get_volume_by_name("test-volume")

    refute_nil volume
    assert_equal "222", volume.id
    assert_equal 20, volume.size
  end

  # API error handling

  def test_api_error_422
    stub_request(:get, "#{@base_url}/networks")
      .to_return(json_response(networks: []))

    stub_request(:post, "#{@base_url}/networks")
      .to_return(json_response({ error: { message: "name already exists" } }, status: 422))

    error = assert_raises(Nvoi::ValidationError) do
      @provider.find_or_create_network("test")
    end
    assert_match(/name already exists/, error.message)
  end

  def test_api_error_404
    stub_request(:get, "#{@base_url}/servers/99999")
      .to_return(json_response({ error: { message: "server not found" } }, status: 404))

    error = assert_raises(Nvoi::NotFoundError) do
      @provider.wait_for_server("99999", 1)
    end
    assert_match(/server not found/, error.message)
  end
end
