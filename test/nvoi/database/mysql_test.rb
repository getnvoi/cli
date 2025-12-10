# frozen_string_literal: true

require "test_helper"

class Nvoi::Database::MysqlTest < Minitest::Test
  def setup
    @provider = Nvoi::Database::Mysql.new
  end

  # parse_url tests
  def test_parse_url_with_full_url
    creds = @provider.parse_url("mysql://myuser:mypass@localhost:3306/mydb")

    assert_equal "myuser", creds.user
    assert_equal "mypass", creds.password
    assert_equal "localhost", creds.host
    assert_equal "3306", creds.port
    assert_equal "mydb", creds.database
  end

  def test_parse_url_without_port_uses_default
    creds = @provider.parse_url("mysql://user:pass@localhost/mydb")

    assert_equal "3306", creds.port
  end

  def test_parse_url_with_different_host
    creds = @provider.parse_url("mysql://user:pass@db.example.com:3307/production")

    assert_equal "db.example.com", creds.host
    assert_equal "3307", creds.port
  end

  # build_url tests
  def test_build_url_from_credentials
    creds = Nvoi::Database::Credentials.new(
      user: "myuser",
      password: "mypass",
      host: "localhost",
      port: "3306",
      database: "mydb"
    )

    url = @provider.build_url(creds)

    assert_equal "mysql://myuser:mypass@localhost:3306/mydb", url
  end

  def test_build_url_with_host_override
    creds = Nvoi::Database::Credentials.new(
      user: "myuser",
      password: "mypass",
      host: "localhost",
      port: "3306",
      database: "mydb"
    )

    url = @provider.build_url(creds, host: "mysql-service")

    assert_equal "mysql://myuser:mypass@mysql-service:3306/mydb", url
  end

  # container_env tests
  def test_container_env_returns_mysql_vars
    creds = Nvoi::Database::Credentials.new(
      user: "myuser",
      password: "mypass",
      database: "mydb"
    )

    env = @provider.container_env(creds)

    assert_equal "myuser", env["MYSQL_USER"]
    assert_equal "mypass", env["MYSQL_PASSWORD"]
    assert_equal "mydb", env["MYSQL_DATABASE"]
    assert_equal "mypass", env["MYSQL_ROOT_PASSWORD"]
    assert_equal 4, env.size
  end

  # app_env tests
  def test_app_env_returns_all_vars
    creds = Nvoi::Database::Credentials.new(
      user: "myuser",
      password: "mypass",
      host: "localhost",
      port: "3306",
      database: "mydb"
    )

    env = @provider.app_env(creds, host: "db-myapp")

    assert_equal "mysql://myuser:mypass@db-myapp:3306/mydb", env["DATABASE_URL"]
    assert_equal "db-myapp", env["MYSQL_HOST"]
    assert_equal "3306", env["MYSQL_PORT"]
    assert_equal "myuser", env["MYSQL_USER"]
    assert_equal "mypass", env["MYSQL_PASSWORD"]
    assert_equal "mydb", env["MYSQL_DATABASE"]
  end

  # default_port tests
  def test_default_port
    assert_equal "3306", @provider.default_port
  end

  # needs_container tests
  def test_needs_container
    assert @provider.needs_container?
  end

  # extension tests
  def test_extension
    assert_equal "sql", @provider.extension
  end

  # dump tests
  def test_dump_executes_mysqldump
    ssh = MockSSH.new("-- MySQL dump")
    opts = Nvoi::Database::DumpOptions.new(
      pod_name: "db-pod-123",
      database: "mydb",
      user: "myuser",
      password: "mypass"
    )

    result = @provider.dump(ssh, opts)

    assert_equal "-- MySQL dump", result
    assert_includes ssh.last_command, "kubectl exec -n default db-pod-123"
    assert_includes ssh.last_command, "mysqldump -u myuser -pmypass mydb"
    assert_includes ssh.last_command, "--single-transaction --routines --triggers"
  end

  def test_dump_raises_on_ssh_error
    ssh = MockSSH.new(nil, raise_error: true)
    opts = Nvoi::Database::DumpOptions.new(
      pod_name: "db-pod",
      database: "mydb",
      user: "myuser",
      password: "mypass"
    )

    error = assert_raises(Nvoi::DatabaseError) { @provider.dump(ssh, opts) }
    assert_includes error.message, "mysqldump failed"
  end

  # restore tests
  def test_restore_creates_database_and_restores
    ssh = MockSSH.new("")
    opts = Nvoi::Database::RestoreOptions.new(
      pod_name: "db-pod-123",
      database: "mydb_restored",
      user: "myuser",
      password: "mypass"
    )
    dump_data = "CREATE TABLE users (id INT);"

    @provider.restore(ssh, dump_data, opts)

    # Should have called: create db, write file, copy to pod, restore, cleanup x2
    assert ssh.commands.length >= 5

    # Verify create database was called
    assert ssh.commands.any? { |cmd| cmd.include?("CREATE DATABASE mydb_restored") }

    # Verify restore command was called
    assert ssh.commands.any? { |cmd| cmd.include?("mysql -u myuser") && cmd.include?("mydb_restored") }
  end

  # create_database tests
  def test_create_database_executes_mysql
    ssh = MockSSH.new("")
    opts = Nvoi::Database::CreateOptions.new(
      pod_name: "db-pod-123",
      database: "newdb",
      user: "myuser",
      password: "mypass"
    )

    @provider.create_database(ssh, opts)

    assert_includes ssh.last_command, "kubectl exec -n default db-pod-123"
    assert_includes ssh.last_command, "mysql -u myuser -pmypass -e"
    assert_includes ssh.last_command, "CREATE DATABASE newdb"
  end

  private

    class MockSSH
      attr_reader :commands, :last_command

      def initialize(response, raise_error: false)
        @response = response
        @raise_error = raise_error
        @commands = []
      end

      def execute(cmd, raise_on_error: true)
        @commands << cmd
        @last_command = cmd
        raise Nvoi::SSHCommandError, "SSH error" if @raise_error && raise_on_error

        @response
      end
    end
end
