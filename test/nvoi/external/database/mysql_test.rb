# frozen_string_literal: true

require "test_helper"

class ExternalDatabaseMysqlTest < Minitest::Test
  def setup
    @provider = Nvoi::External::Database::Mysql.new
  end

  def test_default_port
    assert_equal "3306", @provider.default_port
  end

  def test_needs_container
    assert @provider.needs_container?
  end

  def test_parse_url
    creds = @provider.parse_url("mysql://user:pass@localhost:3306/mydb")

    assert_equal "user", creds.user
    assert_equal "pass", creds.password
    assert_equal "localhost", creds.host
    assert_equal "3306", creds.port
    assert_equal "mydb", creds.database
  end

  def test_build_url
    creds = Nvoi::Objects::Database::Credentials.new(
      user: "user",
      password: "pass",
      host: "localhost",
      port: "3306",
      database: "mydb"
    )

    url = @provider.build_url(creds)
    assert_equal "mysql://user:pass@localhost:3306/mydb", url
  end

  def test_container_env
    creds = Nvoi::Objects::Database::Credentials.new(
      user: "user",
      password: "pass",
      database: "mydb"
    )

    env = @provider.container_env(creds)

    assert_equal "user", env["MYSQL_USER"]
    assert_equal "pass", env["MYSQL_PASSWORD"]
    assert_equal "mydb", env["MYSQL_DATABASE"]
    assert_equal "pass", env["MYSQL_ROOT_PASSWORD"]
  end

  def test_app_env
    creds = Nvoi::Objects::Database::Credentials.new(
      user: "user",
      password: "pass",
      port: "3306",
      database: "mydb"
    )

    env = @provider.app_env(creds, host: "db-service")

    assert_equal "mysql://user:pass@db-service:3306/mydb", env["DATABASE_URL"]
    assert_equal "db-service", env["MYSQL_HOST"]
    assert_equal "3306", env["MYSQL_PORT"]
    assert_equal "user", env["MYSQL_USER"]
    assert_equal "pass", env["MYSQL_PASSWORD"]
    assert_equal "mydb", env["MYSQL_DATABASE"]
  end
end
