# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "webmock/minitest"
require "yaml"
require "nvoi"

# Disable real network connections by default
WebMock.disable_net_connect!

# Test doubles using Struct
MockConfig = Struct.new(:deploy, :container_prefix, :ssh_key_path, :ssh_public_key, keyword_init: true)
MockDeploy = Struct.new(:application, keyword_init: true)
MockApplication = Struct.new(:name, :servers, :app, :database, :services, :ssh_keys, keyword_init: true)
MockServerGroup = Struct.new(:count, :master, :type, :volumes, keyword_init: true)
MockServerVolume = Struct.new(:size, keyword_init: true)
MockSSHKeyConfig = Struct.new(:private_key, :public_key, keyword_init: true)

module TestHelpers
  # Mock config for testing naming and other components
  def mock_config(overrides = {})
    deploy_cfg = overrides[:deploy] || mock_deploy_config
    MockConfig.new(
      deploy: deploy_cfg,
      container_prefix: overrides[:container_prefix] || "testuser-testrepo-myapp",
      ssh_key_path: nil,
      ssh_public_key: nil
    )
  end

  def mock_deploy_config(overrides = {})
    app_cfg = overrides[:application] || mock_application_config
    MockDeploy.new(application: app_cfg)
  end

  def mock_application_config(overrides = {})
    MockApplication.new(
      name: overrides[:name] || "myapp",
      servers: overrides[:servers] || {
        "master" => MockServerGroup.new(
          count: 1,
          master: true,
          type: "cpx11",
          volumes: { "database" => MockServerVolume.new(size: 20) }
        ),
        "workers" => MockServerGroup.new(count: 2, master: false, type: "cpx21", volumes: {})
      },
      app: overrides[:app] || {},
      database: overrides[:database],
      services: overrides[:services] || {},
      ssh_keys: overrides[:ssh_keys]
    )
  end

  # Mock SSH executor that records commands
  class MockSSHExecutor
    attr_reader :executed_commands

    def initialize
      @executed_commands = []
    end

    def execute(cmd)
      @executed_commands << cmd
      ""
    end
  end

  # Fixture helpers
  def fixture_path(name)
    File.join(__dir__, "fixtures", name)
  end

  def load_fixture(name)
    File.read(fixture_path(name))
  end

  # YAML validation helper
  def valid_yaml?(str)
    YAML.safe_load(str, permitted_classes: [Symbol])
    true
  rescue Psych::SyntaxError
    false
  end

  # Parse multi-document YAML
  def parse_yaml_docs(str)
    str.split(/^---\s*$/).reject(&:empty?).map do |doc|
      YAML.safe_load(doc, permitted_classes: [Symbol])
    end
  end

  # Cloudflare API mock helpers
  def stub_cloudflare_tunnel_create(account_id, name, tunnel_id, token)
    stub_request(:post, "https://api.cloudflare.com/client/v4/accounts/#{account_id}/cfd_tunnel")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          success: true,
          result: { id: tunnel_id, name:, token: }
        }.to_json
      )
  end

  def stub_cloudflare_tunnel_find(account_id, name, tunnel_id = nil, token = nil)
    result = tunnel_id ? [{ id: tunnel_id, name:, token: }] : []

    stub_request(:get, "https://api.cloudflare.com/client/v4/accounts/#{account_id}/cfd_tunnel")
      .with(query: hash_including("name" => name))
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { success: true, result: }.to_json
      )
  end

  def stub_cloudflare_zone_find(domain, zone_id)
    stub_request(:get, "https://api.cloudflare.com/client/v4/zones")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { success: true, result: [{ id: zone_id, name: domain }] }.to_json
      )
  end

  def stub_cloudflare_dns_find(zone_id, name, record_type, record_id = nil, content = nil)
    result = record_id ? [{ id: record_id, name:, type: record_type, content:, proxied: true, ttl: 1 }] : []

    stub_request(:get, "https://api.cloudflare.com/client/v4/zones/#{zone_id}/dns_records")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { success: true, result: }.to_json
      )
  end

  def stub_cloudflare_dns_create(zone_id, record_id)
    stub_request(:post, "https://api.cloudflare.com/client/v4/zones/#{zone_id}/dns_records")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          success: true,
          result: { id: record_id, name: "test", type: "CNAME", content: "tunnel.cfargotunnel.com", proxied: true, ttl: 1 }
        }.to_json
      )
  end
end

class Minitest::Test
  include TestHelpers
end
