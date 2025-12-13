# frozen_string_literal: true

require "test_helper"

class ExternalDatabaseSqliteTest < Minitest::Test
  def setup
    @provider = Nvoi::External::Database::Sqlite.new
  end

  def test_default_port
    assert_nil @provider.default_port
  end

  def test_needs_container
    refute @provider.needs_container?
  end

  def test_parse_url
    creds = @provider.parse_url("sqlite://data/production.sqlite3")

    assert_equal "data/production.sqlite3", creds.path
    assert_equal "production.sqlite3", creds.database
  end

  def test_parse_url_with_absolute_path
    creds = @provider.parse_url("sqlite:///var/data/app.db")

    assert_equal "var/data/app.db", creds.path
    assert_equal "app.db", creds.database
  end

  def test_build_url
    creds = Nvoi::External::Database::Types::Credentials.new(
      path: "data/production.sqlite3"
    )

    url = @provider.build_url(creds)
    assert_equal "sqlite://data/production.sqlite3", url
  end

  def test_container_env_empty
    creds = Nvoi::External::Database::Types::Credentials.new(path: "test.db")
    env = @provider.container_env(creds)
    assert_equal({}, env)
  end

  def test_app_env
    creds = Nvoi::External::Database::Types::Credentials.new(
      path: "data/production.sqlite3"
    )

    env = @provider.app_env(creds)

    assert_equal "sqlite://data/production.sqlite3", env["DATABASE_URL"]
  end

  def test_create_database_is_noop
    # Should not raise
    @provider.create_database(nil, nil)
  end
end
