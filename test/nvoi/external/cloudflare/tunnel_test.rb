# frozen_string_literal: true

require "test_helper"

class TunnelTest < Minitest::Test
  def test_tunnel_struct
    tunnel = Nvoi::External::Dns::Tunnel::Record.new(
      id: "tun-123",
      name: "myapp-tunnel",
      token: "secret-token"
    )

    assert_equal "tun-123", tunnel.id
    assert_equal "myapp-tunnel", tunnel.name
    assert_equal "secret-token", tunnel.token
  end

  def test_tunnel_info_struct
    info = Nvoi::External::Dns::Tunnel::Info.new(
      service_name: "myapp-web",
      hostname: "app.example.com",
      tunnel_id: "tun-123",
      tunnel_token: "secret-token",
      port: 3000
    )

    assert_equal "myapp-web", info.service_name
    assert_equal "app.example.com", info.hostname
    assert_equal "tun-123", info.tunnel_id
    assert_equal "secret-token", info.tunnel_token
    assert_equal 3000, info.port
  end
end
