# frozen_string_literal: true

require "test_helper"

class ConfigureTunnelTest < Minitest::Test
  MockConfig = Struct.new(:deploy, :namer, :cloudflare, keyword_init: true)
  MockDeploy = Struct.new(:application, keyword_init: true)
  MockApplication = Struct.new(:app, keyword_init: true)
  MockService = Struct.new(:domain, :subdomain, :port, keyword_init: true)
  MockCloudflare = Struct.new(:api_token, :account_id, keyword_init: true)
  MockNamer = Struct.new(:prefix, keyword_init: true) do
    def tunnel_name(service_name)
      "#{prefix}-#{service_name}"
    end
  end

  def setup
    @log = Minitest::Mock.new
  end

  def test_run_skips_services_without_domain
    services = { "worker" => MockService.new(domain: nil, subdomain: nil, port: nil) }
    app = MockApplication.new(app: services)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new(prefix: "myapp")
    cloudflare = MockCloudflare.new(api_token: "token", account_id: "account")
    config = MockConfig.new(deploy:, namer:, cloudflare:)

    @log.expect(:info, nil, ["Configuring Cloudflare tunnels"])
    @log.expect(:success, nil, ["All tunnels configured (%d)", 0])

    # Mock the Cloudflare client initialization
    Nvoi::External::Dns::Cloudflare.stub(:new, nil) do
      step = Nvoi::Cli::Deploy::Steps::ConfigureTunnel.new(config, @log)
      tunnels = step.run

      assert_equal [], tunnels
    end

    @log.verify
  end

  def test_run_skips_services_without_port
    services = { "web" => MockService.new(domain: "example.com", subdomain: "app", port: nil) }
    app = MockApplication.new(app: services)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new(prefix: "myapp")
    cloudflare = MockCloudflare.new(api_token: "token", account_id: "account")
    config = MockConfig.new(deploy:, namer:, cloudflare:)

    @log.expect(:info, nil, ["Configuring Cloudflare tunnels"])
    @log.expect(:success, nil, ["All tunnels configured (%d)", 0])

    Nvoi::External::Dns::Cloudflare.stub(:new, nil) do
      step = Nvoi::Cli::Deploy::Steps::ConfigureTunnel.new(config, @log)
      tunnels = step.run

      assert_equal [], tunnels
    end

    @log.verify
  end
end
