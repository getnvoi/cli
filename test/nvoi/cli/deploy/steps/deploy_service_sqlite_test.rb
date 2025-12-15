# frozen_string_literal: true

require "test_helper"

class DeployServiceSqliteMountTest < Minitest::Test
  def test_sqlite_database_mount_added_to_app_service
    config = build_config_with_sqlite_mount
    service_config = config.deploy.application.app["web"]

    all_mounts = collect_mounts(service_config, config)

    assert_equal({ "db" => "/app/data" }, all_mounts)
  end

  def test_sqlite_mount_not_added_for_postgres
    config = build_config_with_postgres
    service_config = config.deploy.application.app["web"]

    all_mounts = collect_mounts(service_config, config)

    assert_empty all_mounts
  end

  def test_explicit_app_mount_preserved_with_sqlite
    config = build_config_with_sqlite_and_explicit_mount
    service_config = config.deploy.application.app["web"]

    all_mounts = collect_mounts(service_config, config)

    assert_equal "/app/uploads", all_mounts["uploads"]
    assert_equal "/app/data", all_mounts["db"]
  end

  def test_explicit_app_mount_not_overwritten_by_sqlite
    config = build_config_with_sqlite_and_conflicting_mount
    service_config = config.deploy.application.app["web"]

    all_mounts = collect_mounts(service_config, config)

    # Explicit app mount should take precedence
    assert_equal "/custom/path", all_mounts["db"]
  end

  private

    # Simulates the mount collection logic from DeployService#deploy_app_service
    def collect_mounts(service_config, config)
      all_mounts = (service_config.mounts || {}).dup
      db = config.deploy.application.database
      if db&.adapter&.downcase&.start_with?("sqlite") && db.mount && !db.mount.empty?
        db.mount.each { |k, v| all_mounts[k] ||= v }
      end
      all_mounts
    end

    def build_config_with_sqlite_mount
      data = {
        "application" => {
          "name" => "testapp",
          "servers" => { "master" => { "volumes" => { "db" => { "size" => 10 } } } },
          "app" => { "web" => { "servers" => ["master"], "port" => 3000 } },
          "database" => { "adapter" => "sqlite3", "servers" => ["master"], "mount" => { "db" => "/app/data" } },
          "domain_provider" => { "cloudflare" => { "api_token" => "x", "account_id" => "y" } },
          "compute_provider" => { "scaleway" => { "secret_key" => "x", "project_id" => "y", "server_type" => "DEV1-S", "architecture" => "x86" } }
        }
      }
      deploy = Nvoi::Configuration::Deploy.new(data)
      Nvoi::Configuration::Root.new(deploy)
    end

    def build_config_with_postgres
      data = {
        "application" => {
          "name" => "testapp",
          "servers" => { "master" => {} },
          "app" => { "web" => { "servers" => ["master"], "port" => 3000 } },
          "database" => { "adapter" => "postgres", "servers" => ["master"], "mount" => { "db" => "/var/lib/postgresql" } },
          "domain_provider" => { "cloudflare" => { "api_token" => "x", "account_id" => "y" } },
          "compute_provider" => { "scaleway" => { "secret_key" => "x", "project_id" => "y", "server_type" => "DEV1-S", "architecture" => "x86" } }
        }
      }
      deploy = Nvoi::Configuration::Deploy.new(data)
      Nvoi::Configuration::Root.new(deploy)
    end

    def build_config_with_sqlite_and_explicit_mount
      data = {
        "application" => {
          "name" => "testapp",
          "servers" => { "master" => { "volumes" => { "db" => { "size" => 10 }, "uploads" => { "size" => 20 } } } },
          "app" => { "web" => { "servers" => ["master"], "port" => 3000, "mounts" => { "uploads" => "/app/uploads" } } },
          "database" => { "adapter" => "sqlite3", "servers" => ["master"], "mount" => { "db" => "/app/data" } },
          "domain_provider" => { "cloudflare" => { "api_token" => "x", "account_id" => "y" } },
          "compute_provider" => { "scaleway" => { "secret_key" => "x", "project_id" => "y", "server_type" => "DEV1-S", "architecture" => "x86" } }
        }
      }
      deploy = Nvoi::Configuration::Deploy.new(data)
      Nvoi::Configuration::Root.new(deploy)
    end

    def build_config_with_sqlite_and_conflicting_mount
      data = {
        "application" => {
          "name" => "testapp",
          "servers" => { "master" => { "volumes" => { "db" => { "size" => 10 } } } },
          "app" => { "web" => { "servers" => ["master"], "port" => 3000, "mounts" => { "db" => "/custom/path" } } },
          "database" => { "adapter" => "sqlite3", "servers" => ["master"], "mount" => { "db" => "/app/data" } },
          "domain_provider" => { "cloudflare" => { "api_token" => "x", "account_id" => "y" } },
          "compute_provider" => { "scaleway" => { "secret_key" => "x", "project_id" => "y", "server_type" => "DEV1-S", "architecture" => "x86" } }
        }
      }
      deploy = Nvoi::Configuration::Deploy.new(data)
      Nvoi::Configuration::Root.new(deploy)
    end
end
