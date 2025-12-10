# frozen_string_literal: true

require "test_helper"

class Nvoi::Database::SqliteTest < Minitest::Test
  def setup
    @provider = Nvoi::Database::Sqlite.new
  end

  # parse_url tests
  def test_parse_url_with_relative_path
    creds = @provider.parse_url("sqlite://data/db/production.sqlite3")

    assert_equal "data/db/production.sqlite3", creds.path
    assert_equal "production.sqlite3", creds.database
  end

  def test_parse_url_with_absolute_path
    creds = @provider.parse_url("sqlite:///app/data/app.db")

    assert_equal "app/data/app.db", creds.path
    assert_equal "app.db", creds.database
  end

  def test_parse_url_with_sqlite3_scheme
    creds = @provider.parse_url("sqlite3://data/myapp.db")

    assert_equal "data/myapp.db", creds.path
    assert_equal "myapp.db", creds.database
  end

  def test_parse_url_simple_filename
    creds = @provider.parse_url("sqlite://app.db")

    assert_equal "app.db", creds.path
    assert_equal "app.db", creds.database
  end

  # build_url tests
  def test_build_url_from_credentials
    creds = Nvoi::Database::Credentials.new(
      path: "data/db/production.sqlite3"
    )

    url = @provider.build_url(creds)

    assert_equal "sqlite://data/db/production.sqlite3", url
  end

  def test_build_url_ignores_host_parameter
    creds = Nvoi::Database::Credentials.new(
      path: "app.db"
    )

    url = @provider.build_url(creds, host: "some-host")

    assert_equal "sqlite://app.db", url
  end

  # container_env tests
  def test_container_env_returns_empty_hash
    creds = Nvoi::Database::Credentials.new(
      path: "app.db"
    )

    env = @provider.container_env(creds)

    assert_empty env
  end

  # app_env tests
  def test_app_env_returns_database_url
    creds = Nvoi::Database::Credentials.new(
      path: "data/db/production.sqlite3"
    )

    env = @provider.app_env(creds)

    assert_equal "sqlite://data/db/production.sqlite3", env["DATABASE_URL"]
    assert_equal 1, env.size
  end

  def test_app_env_ignores_host_parameter
    creds = Nvoi::Database::Credentials.new(
      path: "app.db"
    )

    env = @provider.app_env(creds, host: "some-host")

    assert_equal "sqlite://app.db", env["DATABASE_URL"]
  end

  # default_port tests
  def test_default_port_is_nil
    assert_nil @provider.default_port
  end

  # needs_container tests
  def test_does_not_need_container
    refute @provider.needs_container?
  end

  # extension tests
  def test_extension
    assert_equal "sql", @provider.extension
  end

  # dump tests
  def test_dump_executes_sqlite3_dump
    ssh = MockSSH.new("BEGIN TRANSACTION;\nCREATE TABLE users")
    opts = Nvoi::Database::DumpOptions.new(
      host_path: "/opt/nvoi/volumes/myapp-master-db/app.db"
    )

    result = @provider.dump(ssh, opts)

    assert_equal "BEGIN TRANSACTION;\nCREATE TABLE users", result
    assert_equal "sqlite3 /opt/nvoi/volumes/myapp-master-db/app.db .dump", ssh.last_command
  end

  def test_dump_raises_without_host_path
    ssh = MockSSH.new("")
    opts = Nvoi::Database::DumpOptions.new(pod_name: "some-pod")

    error = assert_raises(Nvoi::DatabaseError) { @provider.dump(ssh, opts) }
    assert_includes error.message, "host_path required"
  end

  def test_dump_raises_on_ssh_error
    ssh = MockSSH.new(nil, raise_error: true)
    opts = Nvoi::Database::DumpOptions.new(
      host_path: "/path/to/db.sqlite3"
    )

    error = assert_raises(Nvoi::DatabaseError) { @provider.dump(ssh, opts) }
    assert_includes error.message, "sqlite3 dump failed"
  end

  # restore tests
  def test_restore_creates_new_database_file
    ssh = MockSSH.new("")
    opts = Nvoi::Database::RestoreOptions.new(
      host_path: "/opt/nvoi/volumes/myapp-master-db/app.db",
      database: "mydb_20231210"
    )
    dump_data = "BEGIN TRANSACTION;\nCREATE TABLE users (id INT);"

    result = @provider.restore(ssh, dump_data, opts)

    assert_equal "/opt/nvoi/volumes/myapp-master-db/mydb_20231210.sqlite3", result

    # Verify write command was called
    assert ssh.commands.any? { |cmd| cmd.include?("cat >") && cmd.include?("SQLDUMP") }

    # Verify restore command was called
    assert ssh.commands.any? { |cmd| cmd.include?("sqlite3") && cmd.include?("mydb_20231210.sqlite3") }
  end

  def test_restore_raises_without_host_path
    ssh = MockSSH.new("")
    opts = Nvoi::Database::RestoreOptions.new(database: "newdb")

    error = assert_raises(Nvoi::DatabaseError) { @provider.restore(ssh, "data", opts) }
    assert_includes error.message, "host_path required"
  end

  # create_database tests
  def test_create_database_is_noop
    ssh = MockSSH.new("")
    opts = Nvoi::Database::CreateOptions.new(database: "newdb")

    # Should not raise, should not execute anything
    @provider.create_database(ssh, opts)

    assert_empty ssh.commands
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
