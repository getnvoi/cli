# frozen_string_literal: true

require "test_helper"

class ServerTest < Minitest::Test
  def test_server_struct
    server = Nvoi::External::Cloud::Types::Server::Record.new(
      id: "srv-123",
      name: "web-1",
      status: "running",
      public_ipv4: "1.2.3.4"
    )

    assert_equal "srv-123", server.id
    assert_equal "web-1", server.name
    assert_equal "running", server.status
    assert_equal "1.2.3.4", server.public_ipv4
  end

  def test_server_create_options_struct
    opts = Nvoi::External::Cloud::Types::Server::CreateOptions.new(
      name: "web-1",
      type: "cpx11",
      image: "ubuntu-22.04",
      location: "fsn1",
      user_data: "#!/bin/bash",
      network_id: "net-1",
      firewall_id: "fw-1"
    )

    assert_equal "web-1", opts.name
    assert_equal "cpx11", opts.type
    assert_equal "ubuntu-22.04", opts.image
    assert_equal "fsn1", opts.location
    assert_equal "#!/bin/bash", opts.user_data
    assert_equal "net-1", opts.network_id
    assert_equal "fw-1", opts.firewall_id
  end
end
