# frozen_string_literal: true

require "test_helper"
require_relative "../../../../../lib/nvoi/cli/delete/steps/teardown_network"

class TeardownNetworkStepTest < Minitest::Test
  MockConfig = Struct.new(:network_name, keyword_init: true)

  def test_run_deletes_network
    config = MockConfig.new(network_name: "test-network")

    mock_provider = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    network = Nvoi::Objects::Network.new(id: "net-123", name: "test-network")

    mock_log.expect(:info, nil, ["Deleting network: %s", "test-network"])
    mock_provider.expect(:get_network_by_name, network, ["test-network"])
    mock_provider.expect(:delete_network, nil, ["net-123"])
    mock_log.expect(:success, nil, ["Network deleted"])

    step = Nvoi::Cli::Delete::Steps::TeardownNetwork.new(config, mock_provider, mock_log)
    step.run

    mock_provider.verify
    mock_log.verify
  end

  def test_run_handles_network_not_found_via_exception
    config = MockConfig.new(network_name: "test-network")

    mock_provider = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    mock_log.expect(:info, nil, ["Deleting network: %s", "test-network"])
    mock_provider.expect(:get_network_by_name, nil) { raise Nvoi::NetworkError, "not found" }
    mock_log.expect(:warning, nil, ["Network not found: %s", "not found"])

    step = Nvoi::Cli::Delete::Steps::TeardownNetwork.new(config, mock_provider, mock_log)
    step.run

    mock_log.verify
  end

  def test_run_handles_network_nil_result
    config = MockConfig.new(network_name: "test-network")

    mock_provider = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    mock_log.expect(:info, nil, ["Deleting network: %s", "test-network"])
    mock_provider.expect(:get_network_by_name, nil, ["test-network"])

    step = Nvoi::Cli::Delete::Steps::TeardownNetwork.new(config, mock_provider, mock_log)
    step.run

    mock_provider.verify
    mock_log.verify
  end
end
