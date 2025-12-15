# frozen_string_literal: true

require "test_helper"

class ProvisionNetworkTest < Minitest::Test
  MockConfig = Struct.new(:network_name, :firewall_name, keyword_init: true)
  MockNetwork = Struct.new(:id, keyword_init: true)
  MockFirewall = Struct.new(:id, keyword_init: true)

  def setup
    @log = Minitest::Mock.new
    @provider = Minitest::Mock.new
    @config = MockConfig.new(network_name: "myapp-network", firewall_name: "myapp-firewall")
  end

  def test_run_provisions_network_and_firewall
    @log.expect(:info, nil, ["Provisioning network infrastructure"])
    @log.expect(:info, nil, ["Provisioning network: %s", "myapp-network"])
    @provider.expect(:find_or_create_network, MockNetwork.new(id: "net-123"), ["myapp-network"])
    @log.expect(:success, nil, ["Network ready: %s", "net-123"])
    @log.expect(:info, nil, ["Provisioning firewall: %s", "myapp-firewall"])
    @provider.expect(:find_or_create_firewall, MockFirewall.new(id: "fw-456"), ["myapp-firewall"])
    @log.expect(:success, nil, ["Firewall ready: %s", "fw-456"])
    @log.expect(:success, nil, ["Network infrastructure ready"])

    step = Nvoi::Cli::Deploy::Steps::ProvisionNetwork.new(@config, @provider, @log)
    network, firewall = step.run

    assert_equal "net-123", network.id
    assert_equal "fw-456", firewall.id
    @provider.verify
    @log.verify
  end
end
