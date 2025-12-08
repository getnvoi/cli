# frozen_string_literal: true

require "test_helper"

class Nvoi::Cloudflare::ClientTest < Minitest::Test
  def setup
    @token = "test-api-token"
    @account_id = "test-account-id"
    @client = Nvoi::Cloudflare::Client.new(@token, @account_id)
  end

  # ============================================================================
  # TUNNEL OPERATIONS
  # ============================================================================

  def test_create_tunnel
    stub_request(:post, "https://api.cloudflare.com/client/v4/accounts/#{@account_id}/cfd_tunnel")
      .with(
        headers: { "Authorization" => "Bearer #{@token}" }
      )
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          success: true,
          result: {
            id: "tunnel-123",
            name: "my-tunnel",
            token: "tunnel-token-xyz"
          }
        }.to_json
      )

    tunnel = @client.create_tunnel("my-tunnel")

    assert_equal "tunnel-123", tunnel.id
    assert_equal "my-tunnel", tunnel.name
    assert_equal "tunnel-token-xyz", tunnel.token
  end

  def test_find_tunnel_exists
    stub_request(:get, "https://api.cloudflare.com/client/v4/accounts/#{@account_id}/cfd_tunnel")
      .with(query: hash_including("name" => "my-tunnel"))
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          success: true,
          result: [{ id: "tunnel-123", name: "my-tunnel", token: "token-xyz" }]
        }.to_json
      )

    tunnel = @client.find_tunnel("my-tunnel")

    refute_nil tunnel
    assert_equal "tunnel-123", tunnel.id
    assert_equal "my-tunnel", tunnel.name
  end

  def test_find_tunnel_not_found
    stub_request(:get, "https://api.cloudflare.com/client/v4/accounts/#{@account_id}/cfd_tunnel")
      .with(query: hash_including("name" => "nonexistent"))
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { success: true, result: [] }.to_json
      )

    tunnel = @client.find_tunnel("nonexistent")

    assert_nil tunnel
  end

  def test_get_tunnel_token
    stub_request(:get, "https://api.cloudflare.com/client/v4/accounts/#{@account_id}/cfd_tunnel/tunnel-123/token")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { success: true, result: "tunnel-token-secret" }.to_json
      )

    token = @client.get_tunnel_token("tunnel-123")

    assert_equal "tunnel-token-secret", token
  end

  def test_update_tunnel_configuration
    stub_request(:put, "https://api.cloudflare.com/client/v4/accounts/#{@account_id}/cfd_tunnel/tunnel-123/configurations")
      .with(
        body: hash_including("config")
      )
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { success: true, result: {} }.to_json
      )

    @client.update_tunnel_configuration("tunnel-123", "app.example.com", "http://myapp-web:3000")

    assert_requested :put, "https://api.cloudflare.com/client/v4/accounts/#{@account_id}/cfd_tunnel/tunnel-123/configurations"
  end

  def test_delete_tunnel
    # First, clean up connections
    stub_request(:delete, "https://api.cloudflare.com/client/v4/accounts/#{@account_id}/cfd_tunnel/tunnel-123/connections")
      .to_return(status: 200, body: { success: true }.to_json, headers: { "Content-Type" => "application/json" })

    # Then delete tunnel
    stub_request(:delete, "https://api.cloudflare.com/client/v4/accounts/#{@account_id}/cfd_tunnel/tunnel-123")
      .to_return(status: 200, body: { success: true }.to_json, headers: { "Content-Type" => "application/json" })

    @client.delete_tunnel("tunnel-123")

    assert_requested :delete, "https://api.cloudflare.com/client/v4/accounts/#{@account_id}/cfd_tunnel/tunnel-123"
  end

  def test_delete_tunnel_ignores_connection_cleanup_errors
    stub_request(:delete, "https://api.cloudflare.com/client/v4/accounts/#{@account_id}/cfd_tunnel/tunnel-123/connections")
      .to_return(status: 500, body: { success: false, errors: [{ message: "error" }] }.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:delete, "https://api.cloudflare.com/client/v4/accounts/#{@account_id}/cfd_tunnel/tunnel-123")
      .to_return(status: 200, body: { success: true }.to_json, headers: { "Content-Type" => "application/json" })

    # Should not raise
    @client.delete_tunnel("tunnel-123")
  end

  # ============================================================================
  # DNS OPERATIONS
  # ============================================================================

  def test_find_zone_exists
    stub_request(:get, "https://api.cloudflare.com/client/v4/zones")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          success: true,
          result: [
            { id: "zone-123", name: "example.com" },
            { id: "zone-456", name: "other.com" }
          ]
        }.to_json
      )

    zone = @client.find_zone("example.com")

    refute_nil zone
    assert_equal "zone-123", zone.id
    assert_equal "example.com", zone.name
  end

  def test_find_zone_not_found
    stub_request(:get, "https://api.cloudflare.com/client/v4/zones")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { success: true, result: [] }.to_json
      )

    zone = @client.find_zone("nonexistent.com")

    assert_nil zone
  end

  def test_find_dns_record_exists
    stub_request(:get, "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          success: true,
          result: [
            { id: "record-1", type: "CNAME", name: "app.example.com", content: "tunnel.cfargotunnel.com", proxied: true, ttl: 1 }
          ]
        }.to_json
      )

    record = @client.find_dns_record("zone-123", "app.example.com", "CNAME")

    refute_nil record
    assert_equal "record-1", record.id
    assert_equal "CNAME", record.type
    assert_equal "app.example.com", record.name
  end

  def test_find_dns_record_not_found
    stub_request(:get, "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { success: true, result: [] }.to_json
      )

    record = @client.find_dns_record("zone-123", "nonexistent.example.com", "CNAME")

    assert_nil record
  end

  def test_create_dns_record
    stub_request(:post, "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records")
      .with(
        body: hash_including("type" => "CNAME", "name" => "app.example.com")
      )
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          success: true,
          result: {
            id: "record-new",
            type: "CNAME",
            name: "app.example.com",
            content: "tunnel-123.cfargotunnel.com",
            proxied: true,
            ttl: 1
          }
        }.to_json
      )

    record = @client.create_dns_record("zone-123", "app.example.com", "CNAME", "tunnel-123.cfargotunnel.com")

    assert_equal "record-new", record.id
    assert_equal "CNAME", record.type
    assert_equal "tunnel-123.cfargotunnel.com", record.content
  end

  def test_update_dns_record
    stub_request(:patch, "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records/record-123")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          success: true,
          result: {
            id: "record-123",
            type: "CNAME",
            name: "app.example.com",
            content: "new-tunnel.cfargotunnel.com",
            proxied: true,
            ttl: 1
          }
        }.to_json
      )

    record = @client.update_dns_record("zone-123", "record-123", "app.example.com", "CNAME", "new-tunnel.cfargotunnel.com")

    assert_equal "new-tunnel.cfargotunnel.com", record.content
  end

  def test_create_or_update_creates_when_not_exists
    # find returns nothing
    stub_request(:get, "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { success: true, result: [] }.to_json
      )

    # create is called
    stub_request(:post, "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          success: true,
          result: { id: "new-record", type: "CNAME", name: "new.example.com", content: "target", proxied: true, ttl: 1 }
        }.to_json
      )

    record = @client.create_or_update_dns_record("zone-123", "new.example.com", "CNAME", "target")

    assert_equal "new-record", record.id
  end

  def test_create_or_update_updates_when_exists
    # find returns existing record
    stub_request(:get, "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          success: true,
          result: [{ id: "existing", type: "CNAME", name: "app.example.com", content: "old", proxied: true, ttl: 1 }]
        }.to_json
      )

    # update is called
    stub_request(:patch, "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records/existing")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          success: true,
          result: { id: "existing", type: "CNAME", name: "app.example.com", content: "new-target", proxied: true, ttl: 1 }
        }.to_json
      )

    record = @client.create_or_update_dns_record("zone-123", "app.example.com", "CNAME", "new-target")

    assert_equal "existing", record.id
    assert_equal "new-target", record.content
  end

  def test_delete_dns_record
    stub_request(:delete, "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records/record-123")
      .to_return(status: 200, body: { success: true }.to_json, headers: { "Content-Type" => "application/json" })

    @client.delete_dns_record("zone-123", "record-123")

    assert_requested :delete, "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records/record-123"
  end

  def test_delete_dns_record_idempotent_on_404
    stub_request(:delete, "https://api.cloudflare.com/client/v4/zones/zone-123/dns_records/nonexistent")
      .to_return(status: 404, body: "", headers: {})

    # Should not raise
    @client.delete_dns_record("zone-123", "nonexistent")
  end

  # ============================================================================
  # ERROR HANDLING
  # ============================================================================

  def test_handles_api_error
    stub_request(:get, "https://api.cloudflare.com/client/v4/zones")
      .to_return(
        status: 400,
        headers: { "Content-Type" => "application/json" },
        body: {
          success: false,
          errors: [{ message: "Invalid token" }]
        }.to_json
      )

    assert_raises(Nvoi::CloudflareError) do
      @client.find_zone("example.com")
    end
  end

  def test_handles_multiple_api_errors
    stub_request(:post, "https://api.cloudflare.com/client/v4/accounts/#{@account_id}/cfd_tunnel")
      .to_return(
        status: 400,
        headers: { "Content-Type" => "application/json" },
        body: {
          success: false,
          errors: [
            { message: "Invalid name" },
            { message: "Account suspended" }
          ]
        }.to_json
      )

    error = assert_raises(Nvoi::CloudflareError) do
      @client.create_tunnel("bad-tunnel")
    end

    assert_includes error.message, "Invalid name"
    assert_includes error.message, "Account suspended"
  end

  def test_handles_non_json_response
    stub_request(:get, "https://api.cloudflare.com/client/v4/zones")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "text/html" },
        body: "<html>Error</html>"
      )

    assert_raises(Nvoi::CloudflareError) do
      @client.find_zone("example.com")
    end
  end
end

class Nvoi::Cloudflare::TunnelConfigurationVerificationTest < Minitest::Test
  def setup
    @token = "test-api-token"
    @account_id = "test-account-id"
    @client = Nvoi::Cloudflare::Client.new(@token, @account_id)
  end

  def test_verify_tunnel_configuration_success
    stub_request(:get, "https://api.cloudflare.com/client/v4/accounts/#{@account_id}/cfd_tunnel/tunnel-123/configurations")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          success: true,
          result: {
            config: {
              ingress: [
                { hostname: "app.example.com", service: "http://myapp:3000" },
                { service: "http_status:404" }
              ]
            }
          }
        }.to_json
      )

    result = @client.verify_tunnel_configuration("tunnel-123", "app.example.com", "http://myapp:3000", 1)

    assert result
  end

  def test_verify_tunnel_configuration_timeout
    stub_request(:get, "https://api.cloudflare.com/client/v4/accounts/#{@account_id}/cfd_tunnel/tunnel-123/configurations")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          success: true,
          result: {
            config: {
              ingress: [{ service: "http_status:404" }]
            }
          }
        }.to_json
      )

    # Stub sleep to speed up test
    original_sleep = @client.method(:sleep)
    @client.define_singleton_method(:sleep) { |_| nil }

    begin
      assert_raises(Nvoi::TunnelError) do
        @client.verify_tunnel_configuration("tunnel-123", "app.example.com", "http://myapp:3000", 1)
      end
    ensure
      @client.define_singleton_method(:sleep, original_sleep)
    end
  end
end
