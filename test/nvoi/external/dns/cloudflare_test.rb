# frozen_string_literal: true

require "test_helper"
require "webmock/minitest"

class CloudflareTest < Minitest::Test
  def setup
    WebMock.disable_net_connect!
    @client = Nvoi::External::DNS::Cloudflare.new("test-token", "acc-123")
  end

  def teardown
    WebMock.reset!
  end

  def test_account_id_accessor
    assert_equal "acc-123", @client.account_id
  end

  # Tunnel tests

  def test_create_tunnel
    stub_request(:post, "https://api.cloudflare.com/client/v4/accounts/acc-123/cfd_tunnel")
      .to_return(status: 200, body: {
        success: true,
        result: { id: "tun-123", name: "my-tunnel", token: "tok-abc" }
      }.to_json, headers: { "Content-Type" => "application/json" })

    tunnel = @client.create_tunnel("my-tunnel")

    assert_equal "tun-123", tunnel.id
    assert_equal "my-tunnel", tunnel.name
    assert_equal "tok-abc", tunnel.token
  end

  def test_find_tunnel_returns_tunnel
    stub_request(:get, "https://api.cloudflare.com/client/v4/accounts/acc-123/cfd_tunnel")
      .with(query: { name: "my-tunnel", is_deleted: "false" })
      .to_return(status: 200, body: {
        success: true,
        result: [{ id: "tun-456", name: "my-tunnel", token: "tok-xyz" }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    tunnel = @client.find_tunnel("my-tunnel")

    assert_equal "tun-456", tunnel.id
    assert_equal "my-tunnel", tunnel.name
  end

  def test_find_tunnel_returns_nil_when_not_found
    stub_request(:get, "https://api.cloudflare.com/client/v4/accounts/acc-123/cfd_tunnel")
      .with(query: { name: "nonexistent", is_deleted: "false" })
      .to_return(status: 200, body: {
        success: true,
        result: []
      }.to_json, headers: { "Content-Type" => "application/json" })

    tunnel = @client.find_tunnel("nonexistent")

    assert_nil tunnel
  end

  def test_get_tunnel_token
    stub_request(:get, "https://api.cloudflare.com/client/v4/accounts/acc-123/cfd_tunnel/tun-123/token")
      .to_return(status: 200, body: {
        success: true,
        result: "eyJhbGciOiJIUzI1NiJ9..."
      }.to_json, headers: { "Content-Type" => "application/json" })

    token = @client.get_tunnel_token("tun-123")

    assert_equal "eyJhbGciOiJIUzI1NiJ9...", token
  end

  def test_update_tunnel_configuration
    stub_request(:put, "https://api.cloudflare.com/client/v4/accounts/acc-123/cfd_tunnel/tun-123/configurations")
      .to_return(status: 200, body: {
        success: true,
        result: {}
      }.to_json, headers: { "Content-Type" => "application/json" })

    result = @client.update_tunnel_configuration("tun-123", "app.example.com", "http://localhost:8080")

    assert result["success"]
  end

  def test_delete_tunnel
    stub_request(:delete, "https://api.cloudflare.com/client/v4/accounts/acc-123/cfd_tunnel/tun-123/connections")
      .to_return(status: 200, body: { success: true }.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:delete, "https://api.cloudflare.com/client/v4/accounts/acc-123/cfd_tunnel/tun-123")
      .to_return(status: 200, body: { success: true }.to_json, headers: { "Content-Type" => "application/json" })

    @client.delete_tunnel("tun-123")
  end

  def test_delete_tunnel_handles_connection_cleanup_failure
    stub_request(:delete, "https://api.cloudflare.com/client/v4/accounts/acc-123/cfd_tunnel/tun-456/connections")
      .to_return(status: 500, body: { success: false, errors: [{ message: "error" }] }.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:delete, "https://api.cloudflare.com/client/v4/accounts/acc-123/cfd_tunnel/tun-456")
      .to_return(status: 200, body: { success: true }.to_json, headers: { "Content-Type" => "application/json" })

    @client.delete_tunnel("tun-456")
  end

  # DNS Zone tests

  def test_find_zone_returns_zone
    stub_request(:get, "https://api.cloudflare.com/client/v4/zones")
      .to_return(status: 200, body: {
        success: true,
        result: [{ id: "zone-123", name: "example.com" }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    zone = @client.find_zone("example.com")

    assert_equal "zone-123", zone.id
    assert_equal "example.com", zone.name
  end

  def test_find_zone_returns_nil_when_not_found
    stub_request(:get, "https://api.cloudflare.com/client/v4/zones")
      .to_return(status: 200, body: {
        success: true,
        result: [{ id: "zone-999", name: "other.com" }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    zone = @client.find_zone("example.com")

    assert_nil zone
  end

  # DNS Record tests

  def test_find_dns_record_returns_record
    stub_request(:get, "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records")
      .to_return(status: 200, body: {
        success: true,
        result: [{
          id: "rec-123",
          type: "CNAME",
          name: "app.example.com",
          content: "tunnel.cfargotunnel.com",
          proxied: true,
          ttl: 1
        }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    record = @client.find_dns_record("zone-123", "app.example.com", "CNAME")

    assert_equal "rec-123", record.id
    assert_equal "CNAME", record.type
    assert_equal "app.example.com", record.name
    assert_equal "tunnel.cfargotunnel.com", record.content
    assert record.proxied
  end

  def test_find_dns_record_returns_nil_when_not_found
    stub_request(:get, "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records")
      .to_return(status: 200, body: {
        success: true,
        result: []
      }.to_json, headers: { "Content-Type" => "application/json" })

    record = @client.find_dns_record("zone-123", "app.example.com", "CNAME")

    assert_nil record
  end

  def test_create_dns_record
    stub_request(:post, "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records")
      .to_return(status: 200, body: {
        success: true,
        result: {
          id: "rec-new",
          type: "CNAME",
          name: "app.example.com",
          content: "target.example.com",
          proxied: true,
          ttl: 1
        }
      }.to_json, headers: { "Content-Type" => "application/json" })

    record = @client.create_dns_record("zone-123", "app.example.com", "CNAME", "target.example.com")

    assert_equal "rec-new", record.id
    assert_equal "CNAME", record.type
    assert_equal "app.example.com", record.name
  end

  def test_create_dns_record_not_proxied
    stub_request(:post, "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records")
      .to_return(status: 200, body: {
        success: true,
        result: {
          id: "rec-new",
          type: "A",
          name: "direct.example.com",
          content: "1.2.3.4",
          proxied: false,
          ttl: 300
        }
      }.to_json, headers: { "Content-Type" => "application/json" })

    record = @client.create_dns_record("zone-123", "direct.example.com", "A", "1.2.3.4", proxied: false)

    assert_equal "rec-new", record.id
    refute record.proxied
  end

  def test_update_dns_record
    stub_request(:patch, "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records/rec-123")
      .to_return(status: 200, body: {
        success: true,
        result: {
          id: "rec-123",
          type: "CNAME",
          name: "app.example.com",
          content: "new-target.example.com",
          proxied: true,
          ttl: 1
        }
      }.to_json, headers: { "Content-Type" => "application/json" })

    record = @client.update_dns_record("zone-123", "rec-123", "app.example.com", "CNAME", "new-target.example.com")

    assert_equal "rec-123", record.id
    assert_equal "new-target.example.com", record.content
  end

  def test_create_or_update_dns_record_creates_when_not_exists
    # First find returns nil
    stub_request(:get, "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records")
      .to_return(status: 200, body: {
        success: true,
        result: []
      }.to_json, headers: { "Content-Type" => "application/json" })

    # Then creates
    stub_request(:post, "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records")
      .to_return(status: 200, body: {
        success: true,
        result: {
          id: "rec-new",
          type: "CNAME",
          name: "app.example.com",
          content: "target.example.com",
          proxied: true,
          ttl: 1
        }
      }.to_json, headers: { "Content-Type" => "application/json" })

    record = @client.create_or_update_dns_record("zone-123", "app.example.com", "CNAME", "target.example.com")

    assert_equal "rec-new", record.id
  end

  def test_create_or_update_dns_record_updates_when_exists
    # First find returns existing
    stub_request(:get, "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records")
      .to_return(status: 200, body: {
        success: true,
        result: [{
          id: "rec-existing",
          type: "CNAME",
          name: "app.example.com",
          content: "old-target.example.com",
          proxied: true,
          ttl: 1
        }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    # Then updates
    stub_request(:patch, "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records/rec-existing")
      .to_return(status: 200, body: {
        success: true,
        result: {
          id: "rec-existing",
          type: "CNAME",
          name: "app.example.com",
          content: "new-target.example.com",
          proxied: true,
          ttl: 1
        }
      }.to_json, headers: { "Content-Type" => "application/json" })

    record = @client.create_or_update_dns_record("zone-123", "app.example.com", "CNAME", "new-target.example.com")

    assert_equal "rec-existing", record.id
    assert_equal "new-target.example.com", record.content
  end

  def test_delete_dns_record
    stub_request(:delete, "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records/rec-123")
      .to_return(status: 200, body: { success: true }.to_json, headers: { "Content-Type" => "application/json" })

    @client.delete_dns_record("zone-123", "rec-123")
  end

  def test_delete_dns_record_handles_404
    stub_request(:delete, "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records/rec-nonexistent")
      .to_return(status: 404, body: { success: false }.to_json, headers: { "Content-Type" => "application/json" })

    # Should not raise - 404 is acceptable for idempotent delete
    @client.delete_dns_record("zone-123", "rec-nonexistent")
  end

  # Validation tests

  def test_validate_credentials_success
    stub_request(:get, "https://api.cloudflare.com/client/v4/user/tokens/verify")
      .to_return(status: 200, body: {
        success: true,
        result: { status: "active" }
      }.to_json, headers: { "Content-Type" => "application/json" })

    assert @client.validate_credentials
  end

  def test_validate_credentials_failure
    stub_request(:get, "https://api.cloudflare.com/client/v4/user/tokens/verify")
      .to_return(status: 401, body: {
        success: false,
        errors: [{ message: "Invalid API Token" }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(Nvoi::ValidationError) do
      @client.validate_credentials
    end
  end

  # Error handling tests

  def test_handles_api_error
    stub_request(:get, "https://api.cloudflare.com/client/v4/zones")
      .to_return(status: 400, body: {
        success: false,
        errors: [{ message: "Bad request" }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    assert_raises(Nvoi::CloudflareError) do
      @client.find_zone("example.com")
    end
  end

  def test_handles_multiple_errors
    stub_request(:get, "https://api.cloudflare.com/client/v4/zones")
      .to_return(status: 400, body: {
        success: false,
        errors: [
          { message: "Error 1" },
          { message: "Error 2" }
        ]
      }.to_json, headers: { "Content-Type" => "application/json" })

    error = assert_raises(Nvoi::CloudflareError) do
      @client.find_zone("example.com")
    end

    assert_includes error.message, "Error 1"
    assert_includes error.message, "Error 2"
  end

  def test_handles_unexpected_response_format
    stub_request(:get, "https://api.cloudflare.com/client/v4/zones")
      .to_return(status: 200, body: "not json", headers: { "Content-Type" => "text/plain" })

    assert_raises(Nvoi::CloudflareError) do
      @client.find_zone("example.com")
    end
  end
end
