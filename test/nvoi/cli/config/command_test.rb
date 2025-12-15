# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class ConfigCommandTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir("nvoi-config-test")
    @options = { dir: @temp_dir }
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  def test_init_creates_encrypted_config_and_key
    command = Nvoi::Cli::Config::Command.new(@options)

    # Capture output
    out, _err = capture_io do
      command.init("myapp", "production")
    end

    assert File.exist?(File.join(@temp_dir, "deploy.enc"))
    assert File.exist?(File.join(@temp_dir, "deploy.key"))
    assert_match(/Created deploy.enc/, out)
    assert_match(/Created deploy.key/, out)
  end

  def test_init_updates_gitignore
    command = Nvoi::Cli::Config::Command.new(@options)

    capture_io { command.init("myapp", "production") }

    gitignore = File.read(File.join(@temp_dir, ".gitignore"))
    assert_includes gitignore, "deploy.key"
  end

  def test_domain_set_requires_existing_config
    command = Nvoi::Cli::Config::Command.new(@options)

    _out, err = capture_io do
      command.domain_set("cloudflare", api_token: "token", account_id: "account")
    end

    # Either "Config not found" or "master key not found" depending on state
    assert_match(/not found/, err)
  end

  def test_domain_set_updates_config
    command = Nvoi::Cli::Config::Command.new(@options)
    capture_io { command.init("myapp", "production") }

    out, _err = capture_io do
      command.domain_set("cloudflare", api_token: "cf-token", account_id: "cf-account")
    end

    assert_match(/Config updated/, out)

    # Verify config was updated
    store = Nvoi::Utils::CredentialStore.new(@temp_dir)
    yaml = store.read
    data = YAML.safe_load(yaml)

    assert_equal "cf-token", data.dig("application", "domain_provider", "cloudflare", "api_token")
    assert_equal "cf-account", data.dig("application", "domain_provider", "cloudflare", "account_id")
  end

  def test_server_set_updates_config
    command = Nvoi::Cli::Config::Command.new(@options)
    capture_io { command.init("myapp", "production") }

    out, _err = capture_io do
      command.server_set("main", master: true)
    end

    assert_match(/Config updated/, out)

    store = Nvoi::Utils::CredentialStore.new(@temp_dir)
    yaml = store.read
    data = YAML.safe_load(yaml)

    assert_equal true, data.dig("application", "servers", "main", "master")
  end

  def test_secret_set_updates_config
    command = Nvoi::Cli::Config::Command.new(@options)
    capture_io { command.init("myapp", "production") }

    out, _err = capture_io do
      command.secret_set("DATABASE_URL", "postgres://localhost/db")
    end

    assert_match(/Config updated/, out)

    store = Nvoi::Utils::CredentialStore.new(@temp_dir)
    yaml = store.read
    data = YAML.safe_load(yaml)

    assert_equal "postgres://localhost/db", data.dig("application", "secrets", "DATABASE_URL")
  end

  def test_env_set_updates_config
    command = Nvoi::Cli::Config::Command.new(@options)
    capture_io { command.init("myapp", "production") }

    out, _err = capture_io do
      command.env_set("RAILS_ENV", "production")
    end

    assert_match(/Config updated/, out)

    store = Nvoi::Utils::CredentialStore.new(@temp_dir)
    yaml = store.read
    data = YAML.safe_load(yaml)

    assert_equal "production", data.dig("application", "env", "RAILS_ENV")
  end
end
