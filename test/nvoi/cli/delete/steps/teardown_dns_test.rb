# frozen_string_literal: true

require "test_helper"
require_relative "../../../../../lib/nvoi/cli/delete/steps/teardown_dns"

class TeardownDnsStepTest < Minitest::Test
  MockService = Struct.new(:domain, :subdomain, keyword_init: true)
  MockApplication = Struct.new(:app, keyword_init: true)
  MockDeploy = Struct.new(:application, keyword_init: true)
  MockConfig = Struct.new(:deploy, keyword_init: true)

  def test_run_deletes_dns_records
    service = MockService.new(domain: "example.com", subdomain: "app")
    app = MockApplication.new(app: { "web" => service })
    deploy = MockDeploy.new(application: app)
    config = MockConfig.new(deploy: deploy)

    mock_cf = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    zone = Nvoi::Objects::Zone.new(id: "zone-123", name: "example.com")
    record = Nvoi::Objects::DNSRecord.new(id: "dns-123", name: "app.example.com", type: "CNAME")

    mock_log.expect(:info, nil, ["Deleting DNS record: %s", "app.example.com"])
    mock_cf.expect(:find_zone, zone, ["example.com"])
    mock_cf.expect(:find_dns_record, record, ["zone-123", "app.example.com", "CNAME"])
    mock_cf.expect(:delete_dns_record, nil, ["zone-123", "dns-123"])
    mock_log.expect(:success, nil, ["DNS record deleted: %s", "app.example.com"])

    step = Nvoi::Cli::Delete::Steps::TeardownDns.new(config, mock_cf, mock_log)
    step.run

    mock_cf.verify
    mock_log.verify
  end

  def test_run_handles_zone_not_found
    service = MockService.new(domain: "example.com", subdomain: "app")
    app = MockApplication.new(app: { "web" => service })
    deploy = MockDeploy.new(application: app)
    config = MockConfig.new(deploy: deploy)

    mock_cf = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    mock_log.expect(:info, nil, ["Deleting DNS record: %s", "app.example.com"])
    mock_cf.expect(:find_zone, nil, ["example.com"])
    mock_log.expect(:warning, nil, ["Zone not found: %s", "example.com"])

    step = Nvoi::Cli::Delete::Steps::TeardownDns.new(config, mock_cf, mock_log)
    step.run

    mock_cf.verify
    mock_log.verify
  end

  def test_run_handles_record_not_found
    service = MockService.new(domain: "example.com", subdomain: "app")
    app = MockApplication.new(app: { "web" => service })
    deploy = MockDeploy.new(application: app)
    config = MockConfig.new(deploy: deploy)

    mock_cf = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    zone = Nvoi::Objects::Zone.new(id: "zone-123", name: "example.com")

    mock_log.expect(:info, nil, ["Deleting DNS record: %s", "app.example.com"])
    mock_cf.expect(:find_zone, zone, ["example.com"])
    mock_cf.expect(:find_dns_record, nil, ["zone-123", "app.example.com", "CNAME"])

    step = Nvoi::Cli::Delete::Steps::TeardownDns.new(config, mock_cf, mock_log)
    step.run

    mock_cf.verify
    mock_log.verify
  end

  def test_run_skips_services_without_domain
    service = MockService.new(domain: nil, subdomain: nil)
    app = MockApplication.new(app: { "web" => service })
    deploy = MockDeploy.new(application: app)
    config = MockConfig.new(deploy: deploy)

    mock_cf = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    step = Nvoi::Cli::Delete::Steps::TeardownDns.new(config, mock_cf, mock_log)
    step.run

    # No calls expected
  end

  def test_run_skips_services_without_subdomain
    service = MockService.new(domain: "example.com", subdomain: nil)
    app = MockApplication.new(app: { "web" => service })
    deploy = MockDeploy.new(application: app)
    config = MockConfig.new(deploy: deploy)

    mock_cf = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    step = Nvoi::Cli::Delete::Steps::TeardownDns.new(config, mock_cf, mock_log)
    step.run

    # No calls expected
  end
end
