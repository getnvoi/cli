# frozen_string_literal: true

require "test_helper"

class NetworkTest < Minitest::Test
  def test_network_struct
    network = Nvoi::Objects::Network.new(
      id: "net-123",
      name: "myapp-network",
      ip_range: "10.0.0.0/16"
    )

    assert_equal "net-123", network.id
    assert_equal "myapp-network", network.name
    assert_equal "10.0.0.0/16", network.ip_range
  end
end
