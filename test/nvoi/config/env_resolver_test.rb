# frozen_string_literal: true

require "test_helper"

class Nvoi::Config::EnvResolverTest < Minitest::Test
  def test_injects_deploy_env
    config = build_config(environment: "production")
    resolver = Nvoi::Config::EnvResolver.new(config)

    env = resolver.env_for_service("web")

    assert_equal "production", env["DEPLOY_ENV"]
  end

  def test_injects_database_adapter_for_sqlite
    config = build_config(database: { adapter: "sqlite3" })
    resolver = Nvoi::Config::EnvResolver.new(config)

    env = resolver.env_for_service("web")

    assert_equal "sqlite3", env["DATABASE_ADAPTER"]
  end

  def test_injects_database_url_for_sqlite
    config = build_config(database: { adapter: "sqlite3" })
    resolver = Nvoi::Config::EnvResolver.new(config)

    env = resolver.env_for_service("web")

    assert_equal "sqlite://data/db/production.sqlite3", env["DATABASE_URL"]
  end

  def test_injects_database_adapter_for_postgres
    config = build_config(database: { adapter: "postgres", url: "postgres://localhost/mydb" })
    resolver = Nvoi::Config::EnvResolver.new(config)

    env = resolver.env_for_service("web")

    assert_equal "postgres", env["DATABASE_ADAPTER"]
    assert_equal "postgres://localhost/mydb", env["DATABASE_URL"]
  end

  def test_merges_global_env
    config = build_config(env: { "APP_NAME" => "myapp", "LOG_LEVEL" => "info" })
    resolver = Nvoi::Config::EnvResolver.new(config)

    env = resolver.env_for_service("web")

    assert_equal "myapp", env["APP_NAME"]
    assert_equal "info", env["LOG_LEVEL"]
  end

  def test_merges_global_secrets
    config = build_config(secrets: { "API_KEY" => "secret123" })
    resolver = Nvoi::Config::EnvResolver.new(config)

    env = resolver.env_for_service("web")

    assert_equal "secret123", env["API_KEY"]
  end

  def test_merges_service_specific_env
    config = build_config(
      env: { "GLOBAL" => "value" },
      app: { "web" => { env: { "SERVICE_VAR" => "service_value" } } }
    )
    resolver = Nvoi::Config::EnvResolver.new(config)

    env = resolver.env_for_service("web")

    assert_equal "value", env["GLOBAL"]
    assert_equal "service_value", env["SERVICE_VAR"]
  end

  def test_service_env_overrides_global_env
    config = build_config(
      env: { "LOG_LEVEL" => "info" },
      app: { "web" => { env: { "LOG_LEVEL" => "debug" } } }
    )
    resolver = Nvoi::Config::EnvResolver.new(config)

    env = resolver.env_for_service("web")

    assert_equal "debug", env["LOG_LEVEL"]
  end

  def test_no_database_vars_when_no_database_configured
    config = build_config(database: nil)
    resolver = Nvoi::Config::EnvResolver.new(config)

    env = resolver.env_for_service("web")

    refute env.key?("DATABASE_ADAPTER")
    refute env.key?("DATABASE_URL")
  end

  def test_injects_database_secrets
    config = build_config(database: { adapter: "postgres", secrets: { "DB_PASSWORD" => "secret" } })
    resolver = Nvoi::Config::EnvResolver.new(config)

    env = resolver.env_for_service("web")

    assert_equal "secret", env["DB_PASSWORD"]
  end

  private

    def build_config(environment: "production", env: {}, secrets: {}, database: nil, app: {})
      EnvResolverTestConfig.new(
        environment:,
        env:,
        secrets:,
        database:,
        app:
      )
    end

    class EnvResolverTestConfig
      def initialize(environment:, env:, secrets:, database:, app:)
        @environment = environment
        @env = env
        @secrets = secrets
        @database = database
        @app = app
      end

      def deploy
        @deploy ||= EnvResolverTestDeploy.new(@environment, @env, @secrets, @database, @app)
      end
    end

    class EnvResolverTestDeploy
      def initialize(environment, env, secrets, database, app)
        @environment = environment
        @env = env
        @secrets = secrets
        @database = database
        @app = app
      end

      def application
        @application ||= EnvResolverTestApplication.new(@environment, @env, @secrets, @database, @app)
      end
    end

    class EnvResolverTestApplication
      attr_reader :environment, :env, :secrets

      def initialize(environment, env, secrets, database, app)
        @environment = environment
        @env = env
        @secrets = secrets
        @database_config = database
        @app_config = app
      end

      def database
        return nil unless @database_config

        EnvResolverTestDatabase.new(@database_config)
      end

      def app
        @app_config.transform_values { |v| EnvResolverTestService.new(v) }
      end
    end

    class EnvResolverTestDatabase
      attr_reader :adapter, :url, :secrets

      def initialize(config)
        @adapter = config[:adapter]
        @url = config[:url]
        @secrets = config[:secrets]
      end
    end

    class EnvResolverTestService
      attr_reader :env

      def initialize(config)
        @env = config[:env]
      end
    end
end
