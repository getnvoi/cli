# frozen_string_literal: true

require "test_helper"

class TeardownFirewallStepTest < Minitest::Test
  MockConfig = Struct.new(:firewall_name, keyword_init: true)

  def test_run_deletes_firewall
    config = MockConfig.new(firewall_name: "test-firewall")

    mock_provider = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    firewall = Nvoi::Objects::Firewall::Record.new(id: "fw-123", name: "test-firewall")

    mock_log.expect(:info, nil, ["Deleting firewall: %s", "test-firewall"])
    mock_provider.expect(:get_firewall_by_name, firewall, ["test-firewall"])
    mock_provider.expect(:delete_firewall, nil, ["fw-123"])
    mock_log.expect(:success, nil, ["Firewall deleted"])

    step = Nvoi::Cli::Delete::Steps::TeardownFirewall.new(config, mock_provider, mock_log)
    step.run

    mock_provider.verify
    mock_log.verify
  end

  def test_run_handles_firewall_not_found
    config = MockConfig.new(firewall_name: "test-firewall")

    mock_provider = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    mock_log.expect(:info, nil, ["Deleting firewall: %s", "test-firewall"])
    mock_provider.expect(:get_firewall_by_name, nil) { raise Nvoi::Errors::FirewallError, "not found" }
    mock_log.expect(:warning, nil, ["Firewall not found: %s", "not found"])

    step = Nvoi::Cli::Delete::Steps::TeardownFirewall.new(config, mock_provider, mock_log)
    step.run

    mock_log.verify
  end
end
