# frozen_string_literal: true

require "test_helper"

class ProvisionNetworkStepTest < Minitest::Test
  def setup
    @mock_config = Minitest::Mock.new
    @mock_provider = Minitest::Mock.new
    @mock_log = Minitest::Mock.new

    # network_name and firewall_name are accessed multiple times
    @mock_config.expect(:network_name, "test-network")
    @mock_config.expect(:network_name, "test-network")
    @mock_config.expect(:firewall_name, "test-firewall")
    @mock_config.expect(:firewall_name, "test-firewall")
  end

  def test_run_provisions_network_and_firewall
    network = Nvoi::Objects::Network::Record.new(id: "net-123", name: "test-network")
    firewall = Nvoi::Objects::Firewall::Record.new(id: "fw-123", name: "test-firewall")

    @mock_log.expect(:info, nil, ["Provisioning network infrastructure"])
    @mock_log.expect(:info, nil, ["Provisioning network: %s", "test-network"])
    @mock_provider.expect(:find_or_create_network, network, ["test-network"])
    @mock_log.expect(:success, nil, ["Network ready: %s", "net-123"])
    @mock_log.expect(:info, nil, ["Provisioning firewall: %s", "test-firewall"])
    @mock_provider.expect(:find_or_create_firewall, firewall, ["test-firewall"])
    @mock_log.expect(:success, nil, ["Firewall ready: %s", "fw-123"])
    @mock_log.expect(:success, nil, ["Network infrastructure ready"])

    step = Nvoi::Cli::Deploy::Steps::ProvisionNetwork.new(@mock_config, @mock_provider, @mock_log)
    result_network, result_firewall = step.run

    assert_equal network, result_network
    assert_equal firewall, result_firewall

    @mock_provider.verify
    @mock_log.verify
  end
end
