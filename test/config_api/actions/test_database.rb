# frozen_string_literal: true

require "test_helper"

class TestDatabaseActions < Minitest::Test
  def setup
    @config_with_server = { "application" => { "servers" => { "db" => {} } } }
  end

  # SetDatabase

  def test_set_postgres_database
    result = Nvoi::ConfigApi.set_database(
      @config_with_server,
      servers: ["db"],
      adapter: "postgres",
      user: "appuser",
      password: "secret123",
      database: "app_production"
    )

    assert result.success?

    db = result.data["application"]["database"]
    assert_equal ["db"], db["servers"]
    assert_equal "postgres", db["adapter"]
    assert_equal "appuser", db["secrets"]["POSTGRES_USER"]
    assert_equal "secret123", db["secrets"]["POSTGRES_PASSWORD"]
    assert_equal "app_production", db["secrets"]["POSTGRES_DB"]
  end

  def test_set_mysql_database
    result = Nvoi::ConfigApi.set_database(
      @config_with_server,
      servers: ["db"],
      adapter: "mysql",
      user: "root",
      password: "pass",
      database: "mydb"
    )

    assert result.success?

    db = result.data["application"]["database"]
    assert_equal "mysql", db["adapter"]
    assert_equal "root", db["secrets"]["MYSQL_USER"]
    assert_equal "pass", db["secrets"]["MYSQL_PASSWORD"]
    assert_equal "mydb", db["secrets"]["MYSQL_DATABASE"]
  end

  def test_set_sqlite_database
    result = Nvoi::ConfigApi.set_database(
      @config_with_server,
      servers: ["db"],
      adapter: "sqlite3",
      path: "/app/data/db.sqlite",
      mount: { "data" => "/app/data" }
    )

    assert result.success?

    db = result.data["application"]["database"]
    assert_equal "sqlite3", db["adapter"]
    assert_equal "/app/data/db.sqlite", db["path"]
    assert_equal({ "data" => "/app/data" }, db["mount"])
    assert_nil db["secrets"]
  end

  def test_set_database_with_url
    result = Nvoi::ConfigApi.set_database(
      @config_with_server,
      servers: ["db"],
      adapter: "postgres",
      url: "postgres://user:pass@host:5432/db"
    )

    assert result.success?
    assert_equal "postgres://user:pass@host:5432/db", result.data["application"]["database"]["url"]
  end

  def test_set_database_with_custom_image
    result = Nvoi::ConfigApi.set_database(
      @config_with_server,
      servers: ["db"],
      adapter: "postgres",
      image: "postgres:16-alpine",
      user: "u",
      password: "p",
      database: "d"
    )

    assert result.success?
    assert_equal "postgres:16-alpine", result.data["application"]["database"]["image"]
  end

  def test_set_database_replaces_existing
    config = {
      "application" => {
        "servers" => { "db" => {} },
        "database" => { "adapter" => "mysql", "servers" => ["db"] }
      }
    }

    result = Nvoi::ConfigApi.set_database(
      config,
      servers: ["db"],
      adapter: "postgres",
      user: "u",
      password: "p",
      database: "d"
    )

    assert result.success?
    assert_equal "postgres", result.data["application"]["database"]["adapter"]
  end

  def test_set_database_fails_without_servers
    result = Nvoi::ConfigApi.set_database(@config_with_server, adapter: "postgres")

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  def test_set_database_fails_without_adapter
    result = Nvoi::ConfigApi.set_database(@config_with_server, servers: ["db"])

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  def test_set_database_fails_with_invalid_adapter
    result = Nvoi::ConfigApi.set_database(@config_with_server, servers: ["db"], adapter: "mongodb")

    assert result.failure?
    assert_equal :invalid_args, result.error_type
    assert_match(/must be one of/, result.error_message)
  end

  def test_set_database_fails_if_server_not_found
    result = Nvoi::ConfigApi.set_database(@config_with_server, servers: ["nonexistent"], adapter: "postgres")

    assert result.failure?
    assert_equal :validation_error, result.error_type
  end

  # DeleteDatabase

  def test_delete_database
    config = {
      "application" => {
        "servers" => { "db" => {} },
        "database" => { "adapter" => "postgres", "servers" => ["db"] }
      }
    }

    result = Nvoi::ConfigApi.delete_database(config)

    assert result.success?
    assert_nil result.data["application"]["database"]
  end

  def test_delete_database_when_none_exists
    result = Nvoi::ConfigApi.delete_database(@config_with_server)

    assert result.success? # Idempotent
  end
end
