# frozen_string_literal: true

require "test_helper"
require_relative "../../../../../lib/nvoi/cli/delete/steps/teardown_tunnel"

class TeardownTunnelStepTest < Minitest::Test
  MockNamer = Struct.new(:app_name) do
    def tunnel_name(service_name)
      "#{app_name}-#{service_name}-tunnel"
    end
  end

  MockService = Struct.new(:domain, :subdomain, keyword_init: true)
  MockApplication = Struct.new(:app, keyword_init: true)
  MockDeploy = Struct.new(:application, keyword_init: true)
  MockConfig = Struct.new(:deploy, :namer, keyword_init: true)

  def test_run_deletes_tunnel
    service = MockService.new(domain: "example.com", subdomain: "app")
    app = MockApplication.new(app: { "web" => service })
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new("myapp")
    config = MockConfig.new(deploy: deploy, namer: namer)

    mock_cf = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    tunnel = Nvoi::Objects::Tunnel.new(id: "tun-123", name: "myapp-web-tunnel")

    mock_log.expect(:info, nil, ["Deleting Cloudflare tunnel: %s", "myapp-web-tunnel"])
    mock_cf.expect(:find_tunnel, tunnel, ["myapp-web-tunnel"])
    mock_cf.expect(:delete_tunnel, nil, ["tun-123"])
    mock_log.expect(:success, nil, ["Tunnel deleted: %s", "myapp-web-tunnel"])

    step = Nvoi::Cli::Delete::Steps::TeardownTunnel.new(config, mock_cf, mock_log)
    step.run

    mock_cf.verify
    mock_log.verify
  end

  def test_run_handles_tunnel_not_found
    service = MockService.new(domain: "example.com", subdomain: "app")
    app = MockApplication.new(app: { "web" => service })
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new("myapp")
    config = MockConfig.new(deploy: deploy, namer: namer)

    mock_cf = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    mock_log.expect(:info, nil, ["Deleting Cloudflare tunnel: %s", "myapp-web-tunnel"])
    mock_cf.expect(:find_tunnel, nil, ["myapp-web-tunnel"])

    step = Nvoi::Cli::Delete::Steps::TeardownTunnel.new(config, mock_cf, mock_log)
    step.run

    mock_cf.verify
    mock_log.verify
  end

  def test_run_skips_services_without_domain
    service = MockService.new(domain: nil, subdomain: nil)
    app = MockApplication.new(app: { "web" => service })
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new("myapp")
    config = MockConfig.new(deploy: deploy, namer: namer)

    mock_cf = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    step = Nvoi::Cli::Delete::Steps::TeardownTunnel.new(config, mock_cf, mock_log)
    step.run

    # No calls expected
  end

  def test_run_skips_services_without_subdomain
    service = MockService.new(domain: "example.com", subdomain: nil)
    app = MockApplication.new(app: { "web" => service })
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new("myapp")
    config = MockConfig.new(deploy: deploy, namer: namer)

    mock_cf = Minitest::Mock.new
    mock_log = Minitest::Mock.new

    step = Nvoi::Cli::Delete::Steps::TeardownTunnel.new(config, mock_cf, mock_log)
    step.run

    # No calls expected
  end
end
