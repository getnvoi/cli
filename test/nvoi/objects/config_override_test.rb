# frozen_string_literal: true

require "test_helper"

class ConfigOverrideTest < Minitest::Test
  MockAppService = Struct.new(:subdomain, keyword_init: true)
  MockServerConfig = Struct.new(:master, keyword_init: true)
  MockApplication = Struct.new(:name, :app, :servers, keyword_init: true)
  MockDeploy = Struct.new(:application, keyword_init: true)
  MockConfig = Struct.new(:deploy, :namer, :container_prefix, :server_name, :firewall_name, :network_name, :docker_network_name, keyword_init: true)

  def test_apply_prefixes_branch_to_app_name
    config = build_config("myapp", { "web" => MockAppService.new(subdomain: "www") })

    override = Nvoi::Objects::ConfigOverride.new(branch: "staging")
    override.apply(config)

    assert_equal "myapp-staging", config.deploy.application.name
  end

  def test_apply_prefixes_branch_to_subdomain
    config = build_config("myapp", { "web" => MockAppService.new(subdomain: "www") })

    override = Nvoi::Objects::ConfigOverride.new(branch: "staging")
    override.apply(config)

    assert_equal "staging-www", config.deploy.application.app["web"].subdomain
  end

  def test_apply_prefixes_branch_to_multiple_services
    config = build_config("myapp", {
      "web" => MockAppService.new(subdomain: "www"),
      "api" => MockAppService.new(subdomain: "api")
    })

    override = Nvoi::Objects::ConfigOverride.new(branch: "rel")
    override.apply(config)

    assert_equal "rel-www", config.deploy.application.app["web"].subdomain
    assert_equal "rel-api", config.deploy.application.app["api"].subdomain
  end

  def test_raises_error_for_empty_branch
    error = assert_raises(ArgumentError) do
      Nvoi::Objects::ConfigOverride.new(branch: "")
    end
    assert_match(/branch value required/, error.message)
  end

  def test_raises_error_for_nil_branch
    error = assert_raises(ArgumentError) do
      Nvoi::Objects::ConfigOverride.new(branch: nil)
    end
    assert_match(/branch value required/, error.message)
  end

  def test_raises_error_for_invalid_branch_format_uppercase
    error = assert_raises(ArgumentError) do
      Nvoi::Objects::ConfigOverride.new(branch: "Staging")
    end
    assert_match(/invalid branch format/, error.message)
  end

  def test_raises_error_for_invalid_branch_format_special_chars
    error = assert_raises(ArgumentError) do
      Nvoi::Objects::ConfigOverride.new(branch: "my_branch")
    end
    assert_match(/invalid branch format/, error.message)
  end

  def test_accepts_valid_branch_with_hyphens
    override = Nvoi::Objects::ConfigOverride.new(branch: "feature-123")
    assert_equal "feature-123", override.branch
  end

  def test_accepts_valid_branch_alphanumeric
    override = Nvoi::Objects::ConfigOverride.new(branch: "rel2")
    assert_equal "rel2", override.branch
  end

  def test_apply_regenerates_server_name
    config = build_config("myapp", { "web" => MockAppService.new(subdomain: "www") })

    override = Nvoi::Objects::ConfigOverride.new(branch: "staging")
    override.apply(config)

    assert_equal "myapp-staging-master-1", config.server_name
  end

  def test_apply_regenerates_namer
    config = build_config("myapp", { "web" => MockAppService.new(subdomain: "www") })

    override = Nvoi::Objects::ConfigOverride.new(branch: "staging")
    override.apply(config)

    # Namer should produce branched names
    assert_equal "myapp-staging-worker-1", config.namer.server_name("worker", 1)
  end

  private

    def build_config(app_name, services)
      servers = { "master" => MockServerConfig.new(master: true) }
      app = MockApplication.new(name: app_name, app: services, servers:)
      deploy = MockDeploy.new(application: app)
      MockConfig.new(deploy:)
    end
end
