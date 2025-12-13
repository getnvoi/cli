# frozen_string_literal: true

require "test_helper"

class ConfigLoaderTest < Minitest::Test
  def test_get_database_credentials_returns_nil_for_nil_config
    result = Nvoi::Utils::ConfigLoader.get_database_credentials(nil)
    assert_nil result
  end

  def test_get_database_credentials_returns_nil_for_missing_adapter
    db_config = Nvoi::Configuration::DatabaseCfg.new({})
    result = Nvoi::Utils::ConfigLoader.get_database_credentials(db_config)
    assert_nil result
  end

  def test_get_database_credentials_parses_postgres_from_secrets
    db_config = Nvoi::Configuration::DatabaseCfg.new({
      "adapter" => "postgres",
      "secrets" => {
        "POSTGRES_USER" => "admin",
        "POSTGRES_PASSWORD" => "secret",
        "POSTGRES_DB" => "mydb"
      }
    })

    result = Nvoi::Utils::ConfigLoader.get_database_credentials(db_config)

    assert_equal "admin", result.user
    assert_equal "secret", result.password
    assert_equal "mydb", result.database
    assert_equal "5432", result.port # Port is returned as string
  end

  def test_get_database_credentials_parses_mysql_from_secrets
    db_config = Nvoi::Configuration::DatabaseCfg.new({
      "adapter" => "mysql",
      "secrets" => {
        "MYSQL_USER" => "admin",
        "MYSQL_PASSWORD" => "secret",
        "MYSQL_DATABASE" => "mydb"
      }
    })

    result = Nvoi::Utils::ConfigLoader.get_database_credentials(db_config)

    assert_equal "admin", result.user
    assert_equal "secret", result.password
    assert_equal "mydb", result.database
    assert_equal "3306", result.port # Port is returned as string
  end

  def test_get_database_credentials_handles_sqlite
    db_config = Nvoi::Configuration::DatabaseCfg.new({
      "adapter" => "sqlite3"
    })

    result = Nvoi::Utils::ConfigLoader.get_database_credentials(db_config)

    assert_equal "app.db", result.database
  end

  def test_get_database_credentials_raises_for_unsupported_adapter
    db_config = Nvoi::Configuration::DatabaseCfg.new({
      "adapter" => "oracle"
    })

    error = assert_raises(ArgumentError) do
      Nvoi::Utils::ConfigLoader.get_database_credentials(db_config)
    end
    assert_match(/unsupported database adapter/i, error.message)
  end

  def test_get_database_credentials_parses_url_for_postgres
    db_config = Nvoi::Configuration::DatabaseCfg.new({
      "adapter" => "postgres",
      "url" => "postgres://user:pass@localhost:5432/testdb"
    })

    result = Nvoi::Utils::ConfigLoader.get_database_credentials(db_config)

    assert_equal "user", result.user
    assert_equal "pass", result.password
    assert_equal "testdb", result.database
    assert_equal "5432", result.port # Port is returned as string
  end

  def test_generate_keypair_creates_keypair
    # Skip if ssh-keygen is not available
    skip "ssh-keygen not available" unless system("which ssh-keygen > /dev/null 2>&1")

    private_key, public_key = Nvoi::Utils::ConfigLoader.generate_keypair

    assert private_key.start_with?("-----BEGIN OPENSSH PRIVATE KEY-----")
    assert public_key.start_with?("ssh-ed25519")
    assert public_key.include?("nvoi-deploy")
  end
end
