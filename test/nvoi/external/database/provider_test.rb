# frozen_string_literal: true

require "test_helper"

class DatabaseProviderTest < Minitest::Test
  def test_provider_for_returns_postgres_for_postgres
    provider = Nvoi::External::Database.provider_for("postgres")
    assert_instance_of Nvoi::External::Database::Postgres, provider
  end

  def test_provider_for_returns_postgres_for_postgresql
    provider = Nvoi::External::Database.provider_for("postgresql")
    assert_instance_of Nvoi::External::Database::Postgres, provider
  end

  def test_provider_for_returns_mysql_for_mysql
    provider = Nvoi::External::Database.provider_for("mysql")
    assert_instance_of Nvoi::External::Database::Mysql, provider
  end

  def test_provider_for_returns_mysql_for_mysql2
    provider = Nvoi::External::Database.provider_for("mysql2")
    assert_instance_of Nvoi::External::Database::Mysql, provider
  end

  def test_provider_for_returns_sqlite_for_sqlite
    provider = Nvoi::External::Database.provider_for("sqlite")
    assert_instance_of Nvoi::External::Database::Sqlite, provider
  end

  def test_provider_for_returns_sqlite_for_sqlite3
    provider = Nvoi::External::Database.provider_for("sqlite3")
    assert_instance_of Nvoi::External::Database::Sqlite, provider
  end

  def test_provider_for_raises_for_unknown
    error = assert_raises(ArgumentError) do
      Nvoi::External::Database.provider_for("oracle")
    end
    assert_match(/Unsupported database adapter/, error.message)
  end
end

class PostgresProviderTest < Minitest::Test
  def setup
    @provider = Nvoi::External::Database::Postgres.new
  end

  def test_default_port
    assert_equal "5432", @provider.default_port
  end

  def test_needs_container
    assert_equal true, @provider.needs_container?
  end

  def test_parse_url
    creds = @provider.parse_url("postgres://admin:secret@localhost:5432/mydb")

    assert_equal "admin", creds.user
    assert_equal "secret", creds.password
    assert_equal "localhost", creds.host
    assert_equal "5432", creds.port
    assert_equal "mydb", creds.database
  end

  def test_build_url
    creds = Nvoi::External::Database::Credentials.new(
      user: "admin",
      password: "secret",
      host: "db.example.com",
      port: "5432",
      database: "mydb"
    )

    url = @provider.build_url(creds)

    assert_equal "postgresql://admin:secret@db.example.com:5432/mydb", url
  end

  def test_container_env
    creds = Nvoi::External::Database::Credentials.new(
      user: "admin",
      password: "secret",
      database: "mydb"
    )

    env = @provider.container_env(creds)

    assert_equal "admin", env["POSTGRES_USER"]
    assert_equal "secret", env["POSTGRES_PASSWORD"]
    assert_equal "mydb", env["POSTGRES_DB"]
  end

  def test_app_env
    creds = Nvoi::External::Database::Credentials.new(
      user: "admin",
      password: "secret",
      port: "5432",
      database: "mydb"
    )

    env = @provider.app_env(creds, host: "db-svc")

    assert_equal "postgresql://admin:secret@db-svc:5432/mydb", env["DATABASE_URL"]
    assert_equal "db-svc", env["POSTGRES_HOST"]
    assert_equal "5432", env["POSTGRES_PORT"]
  end
end

class MysqlProviderTest < Minitest::Test
  def setup
    @provider = Nvoi::External::Database::Mysql.new
  end

  def test_default_port
    assert_equal "3306", @provider.default_port
  end

  def test_needs_container
    assert_equal true, @provider.needs_container?
  end

  def test_parse_url
    creds = @provider.parse_url("mysql://admin:secret@localhost:3306/mydb")

    assert_equal "admin", creds.user
    assert_equal "secret", creds.password
    assert_equal "localhost", creds.host
    assert_equal "3306", creds.port
    assert_equal "mydb", creds.database
  end

  def test_container_env
    creds = Nvoi::External::Database::Credentials.new(
      user: "admin",
      password: "secret",
      database: "mydb"
    )

    env = @provider.container_env(creds)

    assert_equal "admin", env["MYSQL_USER"]
    assert_equal "secret", env["MYSQL_PASSWORD"]
    assert_equal "mydb", env["MYSQL_DATABASE"]
  end
end

class SqliteProviderTest < Minitest::Test
  def setup
    @provider = Nvoi::External::Database::Sqlite.new
  end

  def test_default_port
    assert_nil @provider.default_port
  end

  def test_needs_container
    assert_equal false, @provider.needs_container?
  end

  def test_parse_url_with_file_path
    # sqlite3:/// strips down to "data/production.sqlite3" (regex sub removes leading slashes)
    creds = @provider.parse_url("sqlite3:///data/production.sqlite3")

    assert_equal "data/production.sqlite3", creds.path
    assert_equal "production.sqlite3", creds.database
  end

  def test_parse_url_with_relative_path
    creds = @provider.parse_url("sqlite3://./db/development.sqlite3")

    assert_equal "./db/development.sqlite3", creds.path
    assert_equal "development.sqlite3", creds.database
  end

  def test_container_env
    creds = Nvoi::External::Database::Credentials.new(
      path: "/data/app.db"
    )

    env = @provider.container_env(creds)

    assert env.empty?
  end

  def test_app_env
    creds = Nvoi::External::Database::Credentials.new(
      path: "/data/app.db",
      host_path: "/mnt/data/app.db"
    )

    env = @provider.app_env(creds, host: nil)

    assert_equal "sqlite:///data/app.db", env["DATABASE_URL"]
  end
end
