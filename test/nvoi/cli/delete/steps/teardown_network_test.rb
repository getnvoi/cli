# frozen_string_literal: true

require "test_helper"

class TeardownNetworkTest < Minitest::Test
  MockConfig = Struct.new(:network_name, keyword_init: true)
  MockNetwork = Struct.new(:id, keyword_init: true)

  def setup
    @log = Minitest::Mock.new
    @provider = Minitest::Mock.new
    @config = MockConfig.new(network_name: "myapp-network")
  end

  def test_run_deletes_network
    @log.expect(:info, nil, ["Deleting network: %s", "myapp-network"])
    @provider.expect(:get_network_by_name, MockNetwork.new(id: "net-123"), ["myapp-network"])
    @provider.expect(:delete_network, nil, ["net-123"])
    @log.expect(:success, nil, ["Network deleted"])

    step = Nvoi::Cli::Delete::Steps::TeardownNetwork.new(@config, @provider, @log)
    step.run

    @provider.verify
    @log.verify
  end

  def test_run_handles_network_not_found
    @log.expect(:info, nil, ["Deleting network: %s", "myapp-network"])
    @provider.expect(:get_network_by_name, nil, ["myapp-network"])

    step = Nvoi::Cli::Delete::Steps::TeardownNetwork.new(@config, @provider, @log)
    step.run

    @provider.verify
    @log.verify
  end

  def test_run_handles_network_error
    @log.expect(:info, nil, ["Deleting network: %s", "myapp-network"])
    @provider.expect(:get_network_by_name, nil) do
      raise Nvoi::Errors::NetworkError, "not found"
    end
    @log.expect(:warning, nil, ["Network not found: %s", "not found"])

    step = Nvoi::Cli::Delete::Steps::TeardownNetwork.new(@config, @provider, @log)
    step.run

    @log.verify
  end
end
