# frozen_string_literal: true

require "test_helper"

class TeardownDnsTest < Minitest::Test
  MockConfig = Struct.new(:deploy, keyword_init: true)
  MockDeploy = Struct.new(:application, keyword_init: true)
  MockApplication = Struct.new(:app, keyword_init: true)
  MockService = Struct.new(:domain, :subdomain, keyword_init: true)
  MockZone = Struct.new(:id, keyword_init: true)
  MockRecord = Struct.new(:id, keyword_init: true)

  def setup
    @log = Minitest::Mock.new
    @cf_client = Minitest::Mock.new
  end

  def test_run_deletes_dns_records
    services = { "web" => MockService.new(domain: "example.com", subdomain: "app") }
    app = MockApplication.new(app: services)
    deploy = MockDeploy.new(application: app)
    config = MockConfig.new(deploy:)

    @cf_client.expect(:find_zone, MockZone.new(id: "zone-123"), ["example.com"])
    @log.expect(:info, nil, ["Deleting DNS record: %s", "app.example.com"])
    @cf_client.expect(:find_dns_record, MockRecord.new(id: "rec-123"), ["zone-123", "app.example.com", "CNAME"])
    @cf_client.expect(:delete_dns_record, nil, ["zone-123", "rec-123"])
    @log.expect(:success, nil, ["DNS record deleted: %s", "app.example.com"])

    step = Nvoi::Cli::Delete::Steps::TeardownDns.new(config, @cf_client, @log)
    step.run

    @cf_client.verify
    @log.verify
  end

  def test_run_handles_apex_domain
    services = { "web" => MockService.new(domain: "example.com", subdomain: nil) }
    app = MockApplication.new(app: services)
    deploy = MockDeploy.new(application: app)
    config = MockConfig.new(deploy:)

    @cf_client.expect(:find_zone, MockZone.new(id: "zone-123"), ["example.com"])
    
    # Apex returns both apex and wildcard
    @log.expect(:info, nil, ["Deleting DNS record: %s", "example.com"])
    @cf_client.expect(:find_dns_record, MockRecord.new(id: "rec-1"), ["zone-123", "example.com", "CNAME"])
    @cf_client.expect(:delete_dns_record, nil, ["zone-123", "rec-1"])
    @log.expect(:success, nil, ["DNS record deleted: %s", "example.com"])
    
    @log.expect(:info, nil, ["Deleting DNS record: %s", "*.example.com"])
    @cf_client.expect(:find_dns_record, MockRecord.new(id: "rec-2"), ["zone-123", "*.example.com", "CNAME"])
    @cf_client.expect(:delete_dns_record, nil, ["zone-123", "rec-2"])
    @log.expect(:success, nil, ["DNS record deleted: %s", "*.example.com"])

    step = Nvoi::Cli::Delete::Steps::TeardownDns.new(config, @cf_client, @log)
    step.run

    @cf_client.verify
    @log.verify
  end

  def test_run_handles_zone_not_found
    services = { "web" => MockService.new(domain: "example.com", subdomain: "app") }
    app = MockApplication.new(app: services)
    deploy = MockDeploy.new(application: app)
    config = MockConfig.new(deploy:)

    @cf_client.expect(:find_zone, nil, ["example.com"])
    @log.expect(:warning, nil, ["Zone not found: %s", "example.com"])

    step = Nvoi::Cli::Delete::Steps::TeardownDns.new(config, @cf_client, @log)
    step.run

    @cf_client.verify
    @log.verify
  end

  def test_run_skips_services_without_domain
    services = { "worker" => MockService.new(domain: nil, subdomain: nil) }
    app = MockApplication.new(app: services)
    deploy = MockDeploy.new(application: app)
    config = MockConfig.new(deploy:)

    step = Nvoi::Cli::Delete::Steps::TeardownDns.new(config, @cf_client, @log)
    step.run

    # Nothing called
  end
end
