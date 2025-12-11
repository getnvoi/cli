# frozen_string_literal: true

require "test_helper"

class ExternalDatabasePostgresTest < Minitest::Test
  def setup
    @provider = Nvoi::External::Database::Postgres.new
  end

  def test_default_port
    assert_equal "5432", @provider.default_port
  end

  def test_needs_container
    assert @provider.needs_container?
  end

  def test_parse_url
    creds = @provider.parse_url("postgres://user:pass@localhost:5432/mydb")

    assert_equal "user", creds.user
    assert_equal "pass", creds.password
    assert_equal "localhost", creds.host
    assert_equal "5432", creds.port
    assert_equal "mydb", creds.database
  end

  def test_parse_url_with_default_port
    creds = @provider.parse_url("postgres://user:pass@localhost/mydb")

    assert_equal "5432", creds.port
  end

  def test_build_url
    creds = Nvoi::Objects::DatabaseCredentials.new(
      user: "user",
      password: "pass",
      host: "localhost",
      port: "5432",
      database: "mydb"
    )

    url = @provider.build_url(creds)
    assert_equal "postgresql://user:pass@localhost:5432/mydb", url
  end

  def test_build_url_with_host_override
    creds = Nvoi::Objects::DatabaseCredentials.new(
      user: "user",
      password: "pass",
      host: "localhost",
      port: "5432",
      database: "mydb"
    )

    url = @provider.build_url(creds, host: "db-service")
    assert_equal "postgresql://user:pass@db-service:5432/mydb", url
  end

  def test_container_env
    creds = Nvoi::Objects::DatabaseCredentials.new(
      user: "user",
      password: "pass",
      database: "mydb"
    )

    env = @provider.container_env(creds)

    assert_equal "user", env["POSTGRES_USER"]
    assert_equal "pass", env["POSTGRES_PASSWORD"]
    assert_equal "mydb", env["POSTGRES_DB"]
  end

  def test_app_env
    creds = Nvoi::Objects::DatabaseCredentials.new(
      user: "user",
      password: "pass",
      port: "5432",
      database: "mydb"
    )

    env = @provider.app_env(creds, host: "db-service")

    assert_equal "postgresql://user:pass@db-service:5432/mydb", env["DATABASE_URL"]
    assert_equal "db-service", env["POSTGRES_HOST"]
    assert_equal "5432", env["POSTGRES_PORT"]
    assert_equal "user", env["POSTGRES_USER"]
    assert_equal "pass", env["POSTGRES_PASSWORD"]
    assert_equal "mydb", env["POSTGRES_DB"]
  end
end
