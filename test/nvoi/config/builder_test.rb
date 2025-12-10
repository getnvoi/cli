# frozen_string_literal: true

require "test_helper"

class Nvoi::Config::BuilderTest < Minitest::Test
  def test_steps_returns_all_steps
    steps = Nvoi::Config::Builder.steps
    assert_kind_of Array, steps
    assert_equal 8, steps.length

    keys = steps.map { |s| s[:key] }
    assert_includes keys, :compute_provider
    assert_includes keys, :domain_provider
    assert_includes keys, :servers
    assert_includes keys, :app_services
  end

  def test_status_empty_config
    status = Nvoi::Config::Builder.status({})

    refute status[:ready_for_deploy]
    assert_equal :compute_provider, status[:next_required]

    # compute_provider should be available (no deps)
    assert status[:steps][:compute_provider][:available]
    refute status[:steps][:compute_provider][:completed]

    # servers should not be available (depends on compute_provider)
    refute status[:steps][:servers][:available]
  end

  def test_set_compute_provider_hetzner
    config = Nvoi::Config::Builder.set_compute_provider({}, {
      provider: :hetzner,
      api_token: "test-token",
      server_type: "cx22",
      server_location: "fsn1"
    })

    assert_equal "test-token", config["application"]["compute_provider"]["hetzner"]["api_token"]
    assert_equal "cx22", config["application"]["compute_provider"]["hetzner"]["server_type"]
    assert_equal "fsn1", config["application"]["compute_provider"]["hetzner"]["server_location"]
  end

  def test_set_compute_provider_aws
    config = Nvoi::Config::Builder.set_compute_provider({}, {
      provider: :aws,
      access_key_id: "AKID123",
      secret_access_key: "secret",
      region: "us-east-1"
    })

    assert_equal "AKID123", config["application"]["compute_provider"]["aws"]["access_key_id"]
    assert_equal "secret", config["application"]["compute_provider"]["aws"]["secret_access_key"]
    assert_equal "us-east-1", config["application"]["compute_provider"]["aws"]["region"]
  end

  def test_set_compute_provider_unknown_raises
    assert_raises(Nvoi::Config::Builder::ValidationError) do
      Nvoi::Config::Builder.set_compute_provider({}, { provider: :unknown })
    end
  end

  def test_set_domain_provider_cloudflare
    config = Nvoi::Config::Builder.set_domain_provider({}, {
      provider: :cloudflare,
      api_token: "cf-token",
      account_id: "acc123"
    })

    assert_equal "cf-token", config["application"]["domain_provider"]["cloudflare"]["api_token"]
    assert_equal "acc123", config["application"]["domain_provider"]["cloudflare"]["account_id"]
  end

  def test_set_servers_requires_compute_provider
    assert_raises(Nvoi::Config::Builder::DependencyError) do
      Nvoi::Config::Builder.set_servers({}, { master: { type: "cx22" } })
    end
  end

  def test_set_servers_with_volumes
    config = build_base_config
    config = Nvoi::Config::Builder.set_servers(config, {
      master: {
        type: "cx32",
        location: "fsn1",
        volumes: {
          database: { size: 20 },
          uploads: { size: 10 }
        }
      }
    })

    servers = config["application"]["servers"]
    assert servers["master"]
    assert servers["master"]["master"], "First server should be marked as master"
    assert_equal "cx32", servers["master"]["type"]
    assert_equal 20, servers["master"]["volumes"]["database"]["size"]
    assert_equal 10, servers["master"]["volumes"]["uploads"]["size"]
  end

  def test_set_database
    config = build_config_with_servers
    config = Nvoi::Config::Builder.set_database(config, {
      adapter: "postgres",
      servers: [:master],
      image: "postgres:15-alpine",
      mount: { database: "/var/lib/postgresql/data" },
      secrets: { POSTGRES_PASSWORD: "secret123" }
    })

    db = config["application"]["database"]
    assert_equal "postgres", db["adapter"]
    assert_equal ["master"], db["servers"]
    assert_equal "/var/lib/postgresql/data", db["mount"]["database"]
    assert_equal "secret123", db["secrets"]["POSTGRES_PASSWORD"]
  end

  def test_set_database_nil_removes_it
    config = build_config_with_servers
    config = Nvoi::Config::Builder.set_database(config, {
      adapter: "postgres",
      servers: [:master]
    })
    assert config["application"]["database"]

    config = Nvoi::Config::Builder.set_database(config, nil)
    refute config["application"]["database"]
  end

  def test_set_app_services
    config = build_config_with_servers_and_domain
    config = Nvoi::Config::Builder.set_app_services(config, {
      web: {
        servers: [:master],
        port: 3000,
        domain: "example.com",
        subdomain: "www",
        mounts: { uploads: "/app/uploads" },
        healthcheck: { type: "http", path: "/health" }
      },
      worker: {
        servers: [:master],
        command: "bundle exec sidekiq"
      }
    })

    app = config["application"]["app"]
    assert_equal 3000, app["web"]["port"]
    assert_equal "example.com", app["web"]["domain"]
    assert_equal "/app/uploads", app["web"]["mounts"]["uploads"]
    assert_equal "http", app["web"]["healthcheck"]["type"]
    assert_equal "bundle exec sidekiq", app["worker"]["command"]
  end

  def test_set_env
    config = Nvoi::Config::Builder.set_env({}, {
      RAILS_ENV: "production",
      LOG_LEVEL: "info"
    })

    env = config["application"]["env"]
    assert_equal "production", env["RAILS_ENV"]
    assert_equal "info", env["LOG_LEVEL"]
  end

  def test_set_secrets
    config = Nvoi::Config::Builder.set_secrets({}, {
      DATABASE_URL: "postgres://..."
    })

    secrets = config["application"]["secrets"]
    assert_equal "postgres://...", secrets["DATABASE_URL"]
  end

  def test_set_name
    config = Nvoi::Config::Builder.set_name({}, "my-awesome-app")
    assert_equal "my-awesome-app", config["application"]["name"]
  end

  def test_status_validates_mounts
    config = build_config_with_servers_and_domain
    # Add app service that mounts a non-existent volume
    config = Nvoi::Config::Builder.set_app_services(config, {
      web: {
        servers: [:master],
        port: 3000,
        mounts: { nonexistent: "/app/data" }
      }
    })

    status = Nvoi::Config::Builder.status(config)
    refute status[:ready_for_deploy]
    assert_includes status[:errors].first, "nonexistent"
    assert_includes status[:errors].first, "no volume named"
  end

  def test_status_validates_multi_server_with_mounts
    config = build_base_config
    config = Nvoi::Config::Builder.set_servers(config, {
      master: { type: "cx22" },
      workers: { type: "cx22", count: 2 }
    })
    config = Nvoi::Config::Builder.set_domain_provider(config, {
      provider: :cloudflare,
      api_token: "token",
      account_id: "acc"
    })
    config = Nvoi::Config::Builder.set_app_services(config, {
      web: {
        servers: [:master, :workers],
        port: 3000,
        mounts: { data: "/app/data" }
      }
    })

    status = Nvoi::Config::Builder.status(config)
    refute status[:ready_for_deploy]
    assert_includes status[:errors].first, "multiple servers"
    assert_includes status[:errors].first, "cannot have mounts"
  end

  def test_status_ready_for_deploy
    config = build_complete_config

    status = Nvoi::Config::Builder.status(config)
    assert status[:ready_for_deploy]
    assert_empty status[:errors]
    assert_nil status[:next_required]
  end

  def test_config_immutability
    original = { "application" => { "name" => "test" } }
    config = Nvoi::Config::Builder.set_compute_provider(original, {
      provider: :hetzner,
      api_token: "token"
    })

    # Original should not be modified
    refute original["application"]["compute_provider"]
    assert config["application"]["compute_provider"]
  end

  private

    def build_base_config
      Nvoi::Config::Builder.set_compute_provider({}, {
        provider: :hetzner,
        api_token: "test-token"
      })
    end

    def build_config_with_servers
      config = build_base_config
      Nvoi::Config::Builder.set_servers(config, {
        master: {
          type: "cx22",
          volumes: { database: { size: 20 } }
        }
      })
    end

    def build_config_with_servers_and_domain
      config = build_config_with_servers
      Nvoi::Config::Builder.set_domain_provider(config, {
        provider: :cloudflare,
        api_token: "cf-token",
        account_id: "acc123"
      })
    end

    def build_complete_config
      config = build_config_with_servers_and_domain
      Nvoi::Config::Builder.set_app_services(config, {
        web: {
          servers: [:master],
          port: 3000,
          domain: "example.com"
        }
      })
    end
end
