# frozen_string_literal: true

require "test_helper"

class TeardownTunnelTest < Minitest::Test
  MockConfig = Struct.new(:deploy, :namer, keyword_init: true)
  MockDeploy = Struct.new(:application, keyword_init: true)
  MockApplication = Struct.new(:app, keyword_init: true)
  MockService = Struct.new(:domain, :subdomain, keyword_init: true)
  MockNamer = Struct.new(:prefix, keyword_init: true) do
    def tunnel_name(service_name)
      "#{prefix}-#{service_name}"
    end
  end
  MockTunnel = Struct.new(:id, keyword_init: true)

  def setup
    @log = Minitest::Mock.new
    @cf_client = Minitest::Mock.new
  end

  def test_run_deletes_tunnel
    services = { "web" => MockService.new(domain: "example.com", subdomain: "app") }
    app = MockApplication.new(app: services)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new(prefix: "myapp")
    config = MockConfig.new(deploy:, namer:)

    @log.expect(:info, nil, ["Deleting Cloudflare tunnel: %s", "myapp-web"])
    @cf_client.expect(:find_tunnel, MockTunnel.new(id: "tun-123"), ["myapp-web"])
    @cf_client.expect(:delete_tunnel, nil, ["tun-123"])
    @log.expect(:success, nil, ["Tunnel deleted: %s", "myapp-web"])

    step = Nvoi::Cli::Delete::Steps::TeardownTunnel.new(config, @cf_client, @log)
    step.run

    @cf_client.verify
    @log.verify
  end

  def test_run_skips_services_without_domain
    services = { "worker" => MockService.new(domain: nil, subdomain: nil) }
    app = MockApplication.new(app: services)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new(prefix: "myapp")
    config = MockConfig.new(deploy:, namer:)

    step = Nvoi::Cli::Delete::Steps::TeardownTunnel.new(config, @cf_client, @log)
    step.run

    # Nothing called
  end

  def test_run_handles_tunnel_not_found
    services = { "web" => MockService.new(domain: "example.com", subdomain: "app") }
    app = MockApplication.new(app: services)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new(prefix: "myapp")
    config = MockConfig.new(deploy:, namer:)

    @log.expect(:info, nil, ["Deleting Cloudflare tunnel: %s", "myapp-web"])
    @cf_client.expect(:find_tunnel, nil, ["myapp-web"])

    step = Nvoi::Cli::Delete::Steps::TeardownTunnel.new(config, @cf_client, @log)
    step.run

    @cf_client.verify
    @log.verify
  end
end
