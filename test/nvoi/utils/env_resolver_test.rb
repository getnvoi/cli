# frozen_string_literal: true

require "test_helper"

class EnvResolverTest < Minitest::Test
  MockAppService = Struct.new(:env, keyword_init: true)
  MockApplication = Struct.new(:env, :secrets, :app, :environment, :database, keyword_init: true)
  MockDeploy = Struct.new(:application, keyword_init: true)
  MockConfig = Struct.new(:deploy, keyword_init: true)

  def test_env_for_service_merges_app_level_and_service_level
    service = MockAppService.new(env: { "SERVICE_VAR" => "service_value" })
    app = MockApplication.new(
      env: { "APP_VAR" => "app_value" },
      secrets: {},
      app: { "web" => service },
      environment: "production",
      database: nil
    )
    deploy = MockDeploy.new(application: app)
    config = MockConfig.new(deploy:)

    resolver = Nvoi::Utils::EnvResolver.new(config)
    result = resolver.env_for_service("web")

    assert_equal "app_value", result["APP_VAR"]
    assert_equal "service_value", result["SERVICE_VAR"]
    assert_equal "production", result["DEPLOY_ENV"]
  end

  def test_env_for_service_includes_secrets
    service = MockAppService.new(env: {})
    app = MockApplication.new(
      env: {},
      secrets: { "SECRET_KEY" => "secret_value" },
      app: { "web" => service },
      environment: "production",
      database: nil
    )
    deploy = MockDeploy.new(application: app)
    config = MockConfig.new(deploy:)

    resolver = Nvoi::Utils::EnvResolver.new(config)
    result = resolver.env_for_service("web")

    assert_equal "secret_value", result["SECRET_KEY"]
  end

  def test_env_for_service_service_overrides_app_level
    service = MockAppService.new(env: { "VAR" => "service_override" })
    app = MockApplication.new(
      env: { "VAR" => "app_value" },
      secrets: {},
      app: { "web" => service },
      environment: "production",
      database: nil
    )
    deploy = MockDeploy.new(application: app)
    config = MockConfig.new(deploy:)

    resolver = Nvoi::Utils::EnvResolver.new(config)
    result = resolver.env_for_service("web")

    assert_equal "service_override", result["VAR"]
  end

  def test_env_for_service_returns_app_level_for_unknown_service
    service = MockAppService.new(env: { "SERVICE_VAR" => "value" })
    app = MockApplication.new(
      env: { "APP_VAR" => "app_value" },
      secrets: { "SECRET" => "secret_value" },
      app: { "web" => service },
      environment: "production",
      database: nil
    )
    deploy = MockDeploy.new(application: app)
    config = MockConfig.new(deploy:)

    resolver = Nvoi::Utils::EnvResolver.new(config)
    result = resolver.env_for_service("unknown")

    assert_equal "app_value", result["APP_VAR"]
    assert_equal "secret_value", result["SECRET"]
    assert_nil result["SERVICE_VAR"]
  end

  MockDatabase = Struct.new(:adapter, :url, :mount, :secrets, keyword_init: true)
  MockApplicationWithName = Struct.new(:env, :secrets, :app, :environment, :database, :name, keyword_init: true)

  def test_sqlite3_database_url_from_mount
    db = MockDatabase.new(adapter: "sqlite3", url: nil, mount: { "db" => "/app/data" }, secrets: {})
    app = MockApplicationWithName.new(
      env: {},
      secrets: {},
      app: {},
      environment: "production",
      database: db,
      name: "myapp"
    )
    deploy = MockDeploy.new(application: app)
    config = MockConfig.new(deploy:)

    resolver = Nvoi::Utils::EnvResolver.new(config)
    result = resolver.env_for_service("web")

    assert_equal "sqlite:///app/data/myapp-database.sqlite3", result["DATABASE_URL"]
  end

  def test_sqlite3_raises_error_without_mount
    db = MockDatabase.new(adapter: "sqlite3", url: nil, mount: nil, secrets: {})
    app = MockApplicationWithName.new(
      env: {},
      secrets: {},
      app: {},
      environment: "production",
      database: db,
      name: "myapp"
    )
    deploy = MockDeploy.new(application: app)
    config = MockConfig.new(deploy:)

    resolver = Nvoi::Utils::EnvResolver.new(config)

    error = assert_raises(Nvoi::Errors::ConfigError) do
      resolver.env_for_service("web")
    end
    assert_match(/sqlite3 requires database.mount/, error.message)
  end

  def test_sqlite3_raises_error_with_empty_mount
    db = MockDatabase.new(adapter: "sqlite3", url: nil, mount: {}, secrets: {})
    app = MockApplicationWithName.new(
      env: {},
      secrets: {},
      app: {},
      environment: "production",
      database: db,
      name: "myapp"
    )
    deploy = MockDeploy.new(application: app)
    config = MockConfig.new(deploy:)

    resolver = Nvoi::Utils::EnvResolver.new(config)

    error = assert_raises(Nvoi::Errors::ConfigError) do
      resolver.env_for_service("web")
    end
    assert_match(/sqlite3 requires database.mount/, error.message)
  end
end
