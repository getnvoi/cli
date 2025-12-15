# frozen_string_literal: true

require "test_helper"

class TeardownFirewallTest < Minitest::Test
  MockConfig = Struct.new(:firewall_name, keyword_init: true)
  MockFirewall = Struct.new(:id, keyword_init: true)

  def setup
    @log = Minitest::Mock.new
    @provider = Minitest::Mock.new
    @config = MockConfig.new(firewall_name: "myapp-firewall")
  end

  def test_run_deletes_firewall
    @log.expect(:info, nil, ["Deleting firewall: %s", "myapp-firewall"])
    @provider.expect(:get_firewall_by_name, MockFirewall.new(id: "fw-123"), ["myapp-firewall"])
    @provider.expect(:delete_firewall, nil, ["fw-123"])
    @log.expect(:success, nil, ["Firewall deleted"])

    step = Nvoi::Cli::Delete::Steps::TeardownFirewall.new(@config, @provider, @log)
    step.run

    @provider.verify
    @log.verify
  end

  def test_run_handles_firewall_not_found
    @log.expect(:info, nil, ["Deleting firewall: %s", "myapp-firewall"])
    @provider.expect(:get_firewall_by_name, nil) do
      raise Nvoi::Errors::FirewallError, "not found"
    end
    @log.expect(:warning, nil, ["Firewall not found: %s", "not found"])

    step = Nvoi::Cli::Delete::Steps::TeardownFirewall.new(@config, @provider, @log)
    step.run

    @log.verify
  end
end
