# frozen_string_literal: true

require "test_helper"

class TestConfigurationBuilder < Minitest::Test
  def setup
    @base_config = { "application" => { "name" => "test" } }
  end

  # ─── Builder Basics ───

  def test_new_creates_empty_config
    builder = Nvoi::Configuration::Builder.new
    assert_equal({ "application" => {} }, builder.to_h)
  end

  def test_from_hash_loads_existing
    builder = Nvoi::Configuration::Builder.from_hash(@base_config)
    assert_equal "test", builder.to_h["application"]["name"]
  end

  def test_to_h_returns_hash
    builder = Nvoi::Configuration::Builder.new
    assert_instance_of Hash, builder.to_h
  end

  def test_to_yaml_returns_string
    builder = Nvoi::Configuration::Builder.new
    builder.name("myapp")
    yaml = builder.to_yaml
    assert_instance_of String, yaml
    assert_match(/myapp/, yaml)
  end

  def test_chained_operations
    builder = Nvoi::Configuration::Builder.new
    builder.name("myapp")
    builder.environment("staging")

    result = builder.server("web", master: true)
    assert result.success?

    result = builder.volume("web", "data", size: 50)
    assert result.success?

    result = builder.app_entry("api", servers: ["web"], port: 3000)
    assert result.success?

    result = builder.env("RAILS_ENV", "production")
    assert result.success?

    result = builder.secret("SECRET_KEY", "abc123")
    assert result.success?

    data = builder.to_h
    assert_equal "myapp", data["application"]["name"]
    assert data["application"]["servers"]["web"]
    assert_equal 50, data["application"]["servers"]["web"]["volumes"]["data"]["size"]
    assert data["application"]["app"]["api"]
    assert_equal "production", data["application"]["env"]["RAILS_ENV"]
    assert_equal "abc123", data["application"]["secrets"]["SECRET_KEY"]
  end

  # ─── Init ───

  def test_init_creates_config_with_ssh_keys
    result = Nvoi::Configuration::Builder.init(name: "myapp", environment: "production")

    assert result.success?
    assert result.config
    assert result.master_key
    assert result.ssh_public_key
  end

  def test_init_fails_without_name
    result = Nvoi::Configuration::Builder.init(name: nil, environment: "production")

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  def test_init_fails_with_empty_name
    result = Nvoi::Configuration::Builder.init(name: "", environment: "production")

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  # ─── Compute Provider ───

  def test_compute_provider_hetzner
    builder = Nvoi::Configuration::Builder.new
    result = builder.compute_provider("hetzner", api_token: "tok", server_type: "cx22", server_location: "fsn1", architecture: "x86")

    assert result.success?
    assert_equal "tok", builder.to_h["application"]["compute_provider"]["hetzner"]["api_token"]
    assert_equal "cx22", builder.to_h["application"]["compute_provider"]["hetzner"]["server_type"]
  end

  def test_compute_provider_aws
    builder = Nvoi::Configuration::Builder.new
    result = builder.compute_provider("aws", access_key_id: "AKIA...", secret_access_key: "secret", region: "us-east-1", instance_type: "t3.micro", architecture: "x86")

    assert result.success?
    assert builder.to_h["application"]["compute_provider"]["aws"]
  end

  def test_compute_provider_scaleway
    builder = Nvoi::Configuration::Builder.new
    result = builder.compute_provider("scaleway", secret_key: "key", project_id: "proj", zone: "fr-par-1", server_type: "DEV1-S", architecture: "x86")

    assert result.success?
    assert builder.to_h["application"]["compute_provider"]["scaleway"]
  end

  def test_compute_provider_fails_with_invalid_provider
    builder = Nvoi::Configuration::Builder.new

    error = assert_raises(ArgumentError) do
      builder.compute_provider("digitalocean", api_token: "tok")
    end
    assert_match(/must be one of/, error.message)
  end

  def test_remove_compute_provider
    builder = Nvoi::Configuration::Builder.new
    builder.compute_provider("hetzner", api_token: "tok", server_type: "cx22", server_location: "fsn1", architecture: "x86")

    result = builder.remove_compute_provider
    assert result.success?
    assert_equal({}, builder.to_h["application"]["compute_provider"])
  end

  # ─── Domain Provider ───

  def test_domain_provider_cloudflare
    builder = Nvoi::Configuration::Builder.new
    result = builder.domain_provider("cloudflare", api_token: "tok", account_id: "acc")

    assert result.success?
    assert_equal "tok", builder.to_h["application"]["domain_provider"]["cloudflare"]["api_token"]
  end

  def test_domain_provider_fails_with_invalid_provider
    builder = Nvoi::Configuration::Builder.new

    error = assert_raises(ArgumentError) do
      builder.domain_provider("route53", api_token: "tok")
    end
    assert_match(/must be one of/, error.message)
  end

  def test_remove_domain_provider
    builder = Nvoi::Configuration::Builder.new
    builder.domain_provider("cloudflare", api_token: "tok", account_id: "acc")

    result = builder.remove_domain_provider
    assert result.success?
    assert_equal({}, builder.to_h["application"]["domain_provider"])
  end

  # ─── Server ───

  def test_server_minimal
    builder = Nvoi::Configuration::Builder.new
    result = builder.server("web")

    assert result.success?
    assert builder.to_h["application"]["servers"].key?("web")
    assert_equal false, builder.to_h["application"]["servers"]["web"]["master"]
    assert_equal 1, builder.to_h["application"]["servers"]["web"]["count"]
  end

  def test_server_with_all_options
    builder = Nvoi::Configuration::Builder.new
    result = builder.server("workers", master: true, type: "cx32", location: "nbg1", count: 3)

    assert result.success?
    server = builder.to_h["application"]["servers"]["workers"]
    assert_equal true, server["master"]
    assert_equal "cx32", server["type"]
    assert_equal "nbg1", server["location"]
    assert_equal 3, server["count"]
  end

  def test_server_updates_existing
    builder = Nvoi::Configuration::Builder.new
    builder.server("web", count: 1)
    builder.server("web", count: 5)

    assert_equal 5, builder.to_h["application"]["servers"]["web"]["count"]
  end

  def test_server_fails_without_name
    builder = Nvoi::Configuration::Builder.new

    error = assert_raises(ArgumentError) do
      builder.server(nil)
    end
    assert_match(/name is required/, error.message)
  end

  def test_server_fails_with_invalid_count
    builder = Nvoi::Configuration::Builder.new

    error = assert_raises(ArgumentError) do
      builder.server("web", count: 0)
    end
    assert_match(/count must be positive/, error.message)
  end

  def test_remove_server
    builder = Nvoi::Configuration::Builder.new
    builder.server("web")
    builder.server("workers")

    result = builder.remove_server("workers")
    assert result.success?
    assert builder.to_h["application"]["servers"].key?("web")
    refute builder.to_h["application"]["servers"].key?("workers")
  end

  def test_remove_server_fails_if_not_found
    builder = Nvoi::Configuration::Builder.new

    error = assert_raises(Nvoi::Errors::ConfigValidationError) do
      builder.remove_server("nonexistent")
    end
    assert_match(/not found/, error.message)
  end

  def test_remove_server_fails_if_referenced_by_app
    builder = Nvoi::Configuration::Builder.new
    builder.server("web")
    builder.app_entry("api", servers: ["web"])

    error = assert_raises(Nvoi::Errors::ConfigValidationError) do
      builder.remove_server("web")
    end
    assert_match(/app\.api references/, error.message)
  end

  def test_remove_server_fails_if_referenced_by_database
    builder = Nvoi::Configuration::Builder.new
    builder.server("db")
    builder.database(servers: ["db"], adapter: "postgres")

    error = assert_raises(Nvoi::Errors::ConfigValidationError) do
      builder.remove_server("db")
    end
    assert_match(/database references/, error.message)
  end

  def test_remove_server_fails_if_referenced_by_service
    builder = Nvoi::Configuration::Builder.new
    builder.server("cache")
    builder.service("redis", servers: ["cache"], image: "redis:latest")

    error = assert_raises(Nvoi::Errors::ConfigValidationError) do
      builder.remove_server("cache")
    end
    assert_match(/services\.redis references/, error.message)
  end

  # ─── Volume ───

  def test_volume_creates_on_server
    builder = Nvoi::Configuration::Builder.new
    builder.server("web")
    result = builder.volume("web", "data", size: 50)

    assert result.success?
    assert_equal 50, builder.to_h["application"]["servers"]["web"]["volumes"]["data"]["size"]
  end

  def test_volume_fails_if_server_not_found
    builder = Nvoi::Configuration::Builder.new

    error = assert_raises(Nvoi::Errors::ConfigValidationError) do
      builder.volume("nonexistent", "data", size: 10)
    end
    assert_match(/server .* not found/, error.message)
  end

  def test_remove_volume
    builder = Nvoi::Configuration::Builder.new
    builder.server("web")
    builder.volume("web", "data", size: 50)

    result = builder.remove_volume("web", "data")
    assert result.success?
    refute builder.to_h["application"]["servers"]["web"]["volumes"].key?("data")
  end

  # ─── App ───

  def test_app_minimal
    builder = Nvoi::Configuration::Builder.new
    builder.server("web")
    result = builder.app_entry("api", servers: ["web"])

    assert result.success?
    assert builder.to_h["application"]["app"].key?("api")
    assert_equal ["web"], builder.to_h["application"]["app"]["api"]["servers"]
  end

  def test_app_with_all_options
    builder = Nvoi::Configuration::Builder.new
    builder.server("web")
    builder.server("workers")

    result = builder.app_entry(
      "api",
      servers: ["web", "workers"],
      domain: "example.com",
      subdomain: "api",
      port: 3000,
      command: "bundle exec puma",
      pre_run_command: "rake db:migrate",
      env: { "LOG_LEVEL" => "info" },
      mounts: { "logs" => "/app/log" }
    )

    assert result.success?

    app = builder.to_h["application"]["app"]["api"]
    assert_equal ["web", "workers"], app["servers"]
    assert_equal "example.com", app["domain"]
    assert_equal "api", app["subdomain"]
    assert_equal 3000, app["port"]
    assert_equal "bundle exec puma", app["command"]
    assert_equal "rake db:migrate", app["pre_run_command"]
    assert_equal({ "LOG_LEVEL" => "info" }, app["env"])
    assert_equal({ "logs" => "/app/log" }, app["mounts"])
  end

  def test_app_updates_existing
    builder = Nvoi::Configuration::Builder.new
    builder.server("web")
    builder.app_entry("api", servers: ["web"], port: 3000)
    builder.app_entry("api", servers: ["web"], port: 4000)

    assert_equal 4000, builder.to_h["application"]["app"]["api"]["port"]
  end

  def test_app_fails_without_name
    builder = Nvoi::Configuration::Builder.new
    builder.server("web")

    error = assert_raises(ArgumentError) do
      builder.app_entry(nil, servers: ["web"])
    end
    assert_match(/name is required/, error.message)
  end

  def test_app_fails_without_servers
    builder = Nvoi::Configuration::Builder.new
    builder.server("web")

    error = assert_raises(ArgumentError) do
      builder.app_entry("api", servers: nil)
    end
    assert_match(/servers is required/, error.message)
  end

  def test_app_fails_with_empty_servers
    builder = Nvoi::Configuration::Builder.new
    builder.server("web")

    error = assert_raises(ArgumentError) do
      builder.app_entry("api", servers: [])
    end
    assert_match(/servers is required/, error.message)
  end

  def test_app_fails_if_server_ref_not_found
    builder = Nvoi::Configuration::Builder.new
    builder.server("web")

    error = assert_raises(Nvoi::Errors::ConfigValidationError) do
      builder.app_entry("api", servers: ["nonexistent"])
    end
    assert_match(/server .* not found/, error.message)
  end

  def test_remove_app
    builder = Nvoi::Configuration::Builder.new
    builder.server("web")
    builder.app_entry("api", servers: ["web"])
    builder.app_entry("worker", servers: ["web"])

    result = builder.remove_app("api")
    assert result.success?
    refute builder.to_h["application"]["app"].key?("api")
    assert builder.to_h["application"]["app"].key?("worker")
  end

  def test_remove_app_fails_if_not_found
    builder = Nvoi::Configuration::Builder.new

    error = assert_raises(Nvoi::Errors::ConfigValidationError) do
      builder.remove_app("nonexistent")
    end
    assert_match(/not found/, error.message)
  end

  # ─── Database ───

  def test_database_postgres
    builder = Nvoi::Configuration::Builder.new
    builder.server("db")
    result = builder.database(servers: ["db"], adapter: "postgres", user: "app", password: "secret", database_name: "myapp")

    assert result.success?
    db = builder.to_h["application"]["database"]
    assert_equal ["db"], db["servers"]
    assert_equal "postgres", db["adapter"]
    assert_equal "app", db["secrets"]["POSTGRES_USER"]
    assert_equal "secret", db["secrets"]["POSTGRES_PASSWORD"]
    assert_equal "myapp", db["secrets"]["POSTGRES_DB"]
  end

  def test_database_mysql
    builder = Nvoi::Configuration::Builder.new
    builder.server("db")
    result = builder.database(servers: ["db"], adapter: "mysql", user: "app", password: "secret", database_name: "myapp")

    assert result.success?
    db = builder.to_h["application"]["database"]
    assert_equal "mysql", db["adapter"]
    assert_equal "app", db["secrets"]["MYSQL_USER"]
  end

  def test_database_sqlite
    builder = Nvoi::Configuration::Builder.new
    builder.server("db")
    result = builder.database(servers: ["db"], adapter: "sqlite3", path: "/app/data/db.sqlite")

    assert result.success?
    db = builder.to_h["application"]["database"]
    assert_equal "sqlite3", db["adapter"]
    assert_equal "/app/data/db.sqlite", db["path"]
  end

  def test_database_fails_without_servers
    builder = Nvoi::Configuration::Builder.new

    error = assert_raises(ArgumentError) do
      builder.database(servers: [], adapter: "postgres")
    end
    assert_match(/servers is required/, error.message)
  end

  def test_database_fails_if_server_not_found
    builder = Nvoi::Configuration::Builder.new

    error = assert_raises(Nvoi::Errors::ConfigValidationError) do
      builder.database(servers: ["nonexistent"], adapter: "postgres")
    end
    assert_match(/server .* not found/, error.message)
  end

  def test_remove_database
    builder = Nvoi::Configuration::Builder.new
    builder.server("db")
    builder.database(servers: ["db"], adapter: "postgres")

    result = builder.remove_database
    assert result.success?
    refute builder.to_h["application"].key?("database")
  end

  # ─── Service ───

  def test_service_minimal
    builder = Nvoi::Configuration::Builder.new
    builder.server("cache")
    result = builder.service("redis", servers: ["cache"], image: "redis:latest")

    assert result.success?
    svc = builder.to_h["application"]["services"]["redis"]
    assert_equal ["cache"], svc["servers"]
    assert_equal "redis:latest", svc["image"]
  end

  def test_service_with_all_options
    builder = Nvoi::Configuration::Builder.new
    builder.server("cache")
    result = builder.service("redis", servers: ["cache"], image: "redis:latest", port: 6379, command: "redis-server", env: { "MAXMEMORY" => "256mb" })

    assert result.success?
    svc = builder.to_h["application"]["services"]["redis"]
    assert_equal 6379, svc["port"]
    assert_equal "redis-server", svc["command"]
    assert_equal({ "MAXMEMORY" => "256mb" }, svc["env"])
  end

  def test_service_fails_without_servers
    builder = Nvoi::Configuration::Builder.new

    error = assert_raises(ArgumentError) do
      builder.service("redis", servers: [], image: "redis:latest")
    end
    assert_match(/servers is required/, error.message)
  end

  def test_service_fails_if_server_not_found
    builder = Nvoi::Configuration::Builder.new

    error = assert_raises(Nvoi::Errors::ConfigValidationError) do
      builder.service("redis", servers: ["nonexistent"], image: "redis:latest")
    end
    assert_match(/server .* not found/, error.message)
  end

  def test_remove_service
    builder = Nvoi::Configuration::Builder.new
    builder.server("cache")
    builder.service("redis", servers: ["cache"], image: "redis:latest")

    result = builder.remove_service("redis")
    assert result.success?
    refute builder.to_h["application"]["services"].key?("redis")
  end

  # ─── Secret/Env ───

  def test_secret_set
    builder = Nvoi::Configuration::Builder.new
    result = builder.secret("API_KEY", "secret123")

    assert result.success?
    assert_equal "secret123", builder.to_h["application"]["secrets"]["API_KEY"]
  end

  def test_secret_remove
    builder = Nvoi::Configuration::Builder.new
    builder.secret("API_KEY", "secret123")

    result = builder.remove_secret("API_KEY")
    assert result.success?
    refute builder.to_h["application"]["secrets"].key?("API_KEY")
  end

  def test_env_set
    builder = Nvoi::Configuration::Builder.new
    result = builder.env("RAILS_ENV", "production")

    assert result.success?
    assert_equal "production", builder.to_h["application"]["env"]["RAILS_ENV"]
  end

  def test_env_remove
    builder = Nvoi::Configuration::Builder.new
    builder.env("RAILS_ENV", "production")

    result = builder.remove_env("RAILS_ENV")
    assert result.success?
    refute builder.to_h["application"]["env"].key?("RAILS_ENV")
  end
end
