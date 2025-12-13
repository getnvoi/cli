# frozen_string_literal: true

require "test_helper"

class DNSTest < Minitest::Test
  def test_zone_struct
    zone = Nvoi::External::Dns::Zone.new(
      id: "zone-123",
      name: "example.com"
    )

    assert_equal "zone-123", zone.id
    assert_equal "example.com", zone.name
  end

  def test_dns_record_struct
    record = Nvoi::External::Dns::Record.new(
      id: "rec-123",
      type: "CNAME",
      name: "app.example.com",
      content: "tunnel.cfargotunnel.com",
      proxied: true,
      ttl: 1
    )

    assert_equal "rec-123", record.id
    assert_equal "CNAME", record.type
    assert_equal "app.example.com", record.name
    assert_equal "tunnel.cfargotunnel.com", record.content
    assert_equal true, record.proxied
    assert_equal 1, record.ttl
  end
end
