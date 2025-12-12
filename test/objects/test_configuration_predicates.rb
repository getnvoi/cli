# frozen_string_literal: true

require "test_helper"

class TestConfigurationPredicates < Minitest::Test
  # ─── AppService Predicates ───

  def test_app_service_web_with_port
    app = Nvoi::Objects::Configuration::AppService.new({ "port" => 3000, "servers" => ["web"] })

    assert app.web?
    refute app.worker?
  end

  def test_app_service_worker_without_port
    app = Nvoi::Objects::Configuration::AppService.new({ "servers" => ["web"] })

    refute app.web?
    assert app.worker?
  end

  def test_app_service_worker_with_zero_port
    app = Nvoi::Objects::Configuration::AppService.new({ "port" => 0, "servers" => ["web"] })

    refute app.web?
    assert app.worker?
  end

  def test_app_service_fqdn_with_subdomain
    app = Nvoi::Objects::Configuration::AppService.new({
      "domain" => "example.com",
      "subdomain" => "api",
      "servers" => ["web"]
    })

    assert_equal "api.example.com", app.fqdn
  end

  def test_app_service_fqdn_without_subdomain
    app = Nvoi::Objects::Configuration::AppService.new({
      "domain" => "example.com",
      "servers" => ["web"]
    })

    assert_equal "example.com", app.fqdn
  end

  def test_app_service_fqdn_nil_when_no_domain
    app = Nvoi::Objects::Configuration::AppService.new({ "servers" => ["web"] })

    assert_nil app.fqdn
  end

  def test_app_service_fqdn_nil_when_empty_domain
    app = Nvoi::Objects::Configuration::AppService.new({
      "domain" => "",
      "servers" => ["web"]
    })

    assert_nil app.fqdn
  end

  # ─── Application Helpers ───

  def test_application_app_by_name
    application = Nvoi::Objects::Configuration::Application.new({
      "app" => {
        "web" => { "port" => 3000, "servers" => ["main"] },
        "worker" => { "servers" => ["main"] }
      }
    })

    app = application.app_by_name("web")
    assert_equal 3000, app.port
  end

  def test_application_app_by_name_returns_nil_for_missing
    application = Nvoi::Objects::Configuration::Application.new({})

    assert_nil application.app_by_name("nonexistent")
  end

  def test_application_server_by_name
    application = Nvoi::Objects::Configuration::Application.new({
      "servers" => {
        "web" => { "master" => true, "count" => 2 },
        "worker" => { "count" => 3 }
      }
    })

    server = application.server_by_name("web")
    assert server.master?
    assert_equal 2, server.count
  end

  def test_application_server_by_name_returns_nil_for_missing
    application = Nvoi::Objects::Configuration::Application.new({})

    assert_nil application.server_by_name("nonexistent")
  end

  def test_application_web_apps
    application = Nvoi::Objects::Configuration::Application.new({
      "app" => {
        "api" => { "port" => 3000, "servers" => ["main"] },
        "worker" => { "servers" => ["main"] },
        "admin" => { "port" => 4000, "servers" => ["main"] }
      }
    })

    web_apps = application.web_apps
    assert_equal 2, web_apps.size
    assert web_apps.key?("api")
    assert web_apps.key?("admin")
    refute web_apps.key?("worker")
  end

  def test_application_workers
    application = Nvoi::Objects::Configuration::Application.new({
      "app" => {
        "api" => { "port" => 3000, "servers" => ["main"] },
        "worker" => { "servers" => ["main"] },
        "scheduler" => { "servers" => ["main"] }
      }
    })

    workers = application.workers
    assert_equal 2, workers.size
    assert workers.key?("worker")
    assert workers.key?("scheduler")
    refute workers.key?("api")
  end

  # ─── Server Predicates ───

  def test_server_master_true
    server = Nvoi::Objects::Configuration::Server.new({ "master" => true })

    assert server.master?
  end

  def test_server_master_false
    server = Nvoi::Objects::Configuration::Server.new({ "master" => false })

    refute server.master?
  end

  def test_server_master_default_false
    server = Nvoi::Objects::Configuration::Server.new({})

    refute server.master?
  end

  def test_server_volume_by_name
    server = Nvoi::Objects::Configuration::Server.new({
      "volumes" => {
        "data" => { "size" => 50 },
        "logs" => { "size" => 10 }
      }
    })

    vol = server.volume("data")
    assert_equal 50, vol.size
  end

  def test_server_volume_by_name_returns_nil_for_missing
    server = Nvoi::Objects::Configuration::Server.new({})

    assert_nil server.volume("nonexistent")
  end

  # ─── Database Predicates ───

  def test_database_postgres
    db = Nvoi::Objects::Configuration::DatabaseCfg.new({ "adapter" => "postgres" })

    assert db.postgres?
    refute db.mysql?
    refute db.sqlite?
  end

  def test_database_postgresql
    db = Nvoi::Objects::Configuration::DatabaseCfg.new({ "adapter" => "postgresql" })

    assert db.postgres?
    refute db.mysql?
    refute db.sqlite?
  end

  def test_database_mysql
    db = Nvoi::Objects::Configuration::DatabaseCfg.new({ "adapter" => "mysql" })

    refute db.postgres?
    assert db.mysql?
    refute db.sqlite?
  end

  def test_database_sqlite
    db = Nvoi::Objects::Configuration::DatabaseCfg.new({ "adapter" => "sqlite3" })

    refute db.postgres?
    refute db.mysql?
    assert db.sqlite?
  end

  def test_database_sqlite_plain
    db = Nvoi::Objects::Configuration::DatabaseCfg.new({ "adapter" => "sqlite" })

    refute db.postgres?
    refute db.mysql?
    assert db.sqlite?
  end

  def test_database_predicates_handle_nil_adapter
    db = Nvoi::Objects::Configuration::DatabaseCfg.new({})

    refute db.postgres?
    refute db.mysql?
    refute db.sqlite?
  end
end
