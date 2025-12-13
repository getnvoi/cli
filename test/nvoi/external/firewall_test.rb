# frozen_string_literal: true

require "test_helper"

class FirewallTest < Minitest::Test
  def test_firewall_struct
    firewall = Nvoi::External::Firewall::Record.new(
      id: "fw-123",
      name: "myapp-firewall"
    )

    assert_equal "fw-123", firewall.id
    assert_equal "myapp-firewall", firewall.name
  end
end
