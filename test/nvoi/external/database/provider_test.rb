# frozen_string_literal: true

require "test_helper"

class ExternalDatabaseProviderTest < Minitest::Test
  def test_provider_for_postgres
    provider = Nvoi::External::Database.provider_for("postgres")
    assert_instance_of Nvoi::External::Database::Postgres, provider
  end

  def test_provider_for_postgresql
    provider = Nvoi::External::Database.provider_for("postgresql")
    assert_instance_of Nvoi::External::Database::Postgres, provider
  end

  def test_provider_for_mysql
    provider = Nvoi::External::Database.provider_for("mysql")
    assert_instance_of Nvoi::External::Database::Mysql, provider
  end

  def test_provider_for_mysql2
    provider = Nvoi::External::Database.provider_for("mysql2")
    assert_instance_of Nvoi::External::Database::Mysql, provider
  end

  def test_provider_for_sqlite
    provider = Nvoi::External::Database.provider_for("sqlite")
    assert_instance_of Nvoi::External::Database::Sqlite, provider
  end

  def test_provider_for_sqlite3
    provider = Nvoi::External::Database.provider_for("sqlite3")
    assert_instance_of Nvoi::External::Database::Sqlite, provider
  end

  def test_provider_for_unknown_raises
    assert_raises(ArgumentError) do
      Nvoi::External::Database.provider_for("unknown")
    end
  end

  def test_base_provider_raises_not_implemented
    provider = Nvoi::External::Database::Provider.new

    assert_raises(NotImplementedError) { provider.parse_url("test") }
    assert_raises(NotImplementedError) { provider.build_url(nil) }
    assert_raises(NotImplementedError) { provider.container_env(nil) }
    assert_raises(NotImplementedError) { provider.app_env(nil, host: "test") }
    assert_raises(NotImplementedError) { provider.dump(nil, nil) }
    assert_raises(NotImplementedError) { provider.restore(nil, nil, nil) }
    assert_raises(NotImplementedError) { provider.create_database(nil, nil) }
    assert_raises(NotImplementedError) { provider.default_port }
  end

  def test_base_provider_extension
    provider = Nvoi::External::Database::Provider.new
    assert_equal "sql", provider.extension
  end

  def test_base_provider_needs_container
    provider = Nvoi::External::Database::Provider.new
    assert provider.needs_container?
  end
end
