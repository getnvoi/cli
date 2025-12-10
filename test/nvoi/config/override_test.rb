# frozen_string_literal: true

require "test_helper"

class Nvoi::Config::OverrideTest < Minitest::Test
  # Validation tests

  def test_requires_branch_value
    error = assert_raises(ArgumentError) do
      Nvoi::Config::Override.new(branch: nil)
    end
    assert_includes error.message, "--branch value required"

    error = assert_raises(ArgumentError) do
      Nvoi::Config::Override.new(branch: "")
    end
    assert_includes error.message, "--branch value required"
  end

  def test_validates_branch_format
    error = assert_raises(ArgumentError) do
      Nvoi::Config::Override.new(branch: "PR_123")
    end
    assert_includes error.message, "invalid branch format"

    error = assert_raises(ArgumentError) do
      Nvoi::Config::Override.new(branch: "my branch!")
    end
    assert_includes error.message, "invalid branch format"
  end

  def test_accepts_valid_branch
    override = Nvoi::Config::Override.new(branch: "pr123")
    assert_instance_of Nvoi::Config::Override, override
    assert_equal "pr123", override.branch
  end

  # Apply tests

  def test_apply_prefixes_app_name
    override = Nvoi::Config::Override.new(branch: "pr123")
    config = build_mock_config(app_name: "myapp", subdomains: { "web" => "app" })

    override.apply(config)

    assert_equal "myapp-pr123", config.deploy.application.name
  end

  def test_apply_prefixes_subdomains
    override = Nvoi::Config::Override.new(branch: "pr123")
    config = build_mock_config(app_name: "myapp", subdomains: { "web" => "app", "api" => "api" })

    override.apply(config)

    assert_equal "pr123-app", config.deploy.application.app["web"].subdomain
    assert_equal "pr123-api", config.deploy.application.app["api"].subdomain
  end

  def test_apply_returns_config
    override = Nvoi::Config::Override.new(branch: "pr123")
    config = build_mock_config(app_name: "myapp", subdomains: { "web" => "app" })

    result = override.apply(config)

    assert_same config, result
  end

  private

    MockDeploy = Struct.new(:application)
    MockApplication = Struct.new(:name, :app, keyword_init: true)
    MockConfig = Struct.new(:deploy)

    def build_mock_config(app_name:, subdomains:)
      app_services = {}
      subdomains.each do |svc_name, subdomain|
        app_services[svc_name] = Nvoi::Config::AppServiceConfig.new({
          "servers" => ["master"],
          "subdomain" => subdomain,
          "port" => 3000
        })
      end

      application = MockApplication.new(name: app_name, app: app_services)
      deploy = MockDeploy.new(application)
      MockConfig.new(deploy)
    end
end
