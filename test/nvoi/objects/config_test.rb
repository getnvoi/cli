# frozen_string_literal: true

require "test_helper"
require_relative "../../../lib/nvoi/objects/config"

class ConfigurationTest < Minitest::Test
  def minimal_hetzner_config_data
    {
      "application" => {
        "name" => "myapp",
        "domain_provider" => {
          "cloudflare" => {
            "api_token" => "cf-token",
            "account_id" => "cf-account-id"
          }
        },
        "compute_provider" => {
          "hetzner" => {
            "api_token" => "hz-token",
            "server_type" => "cpx11",
            "server_location" => "fsn1"
          }
        },
        "servers" => {
          "master" => { "master" => true }
        },
        "app" => {}
      }
    }
  end

  def test_provider_name_returns_hetzner
    deploy = Nvoi::Objects::DeployConfig.new(minimal_hetzner_config_data)
    config = Nvoi::Objects::Configuration.new(deploy)

    assert_equal "hetzner", config.provider_name
  end

  def test_provider_name_returns_aws
    data = {
      "application" => {
        "name" => "myapp",
        "domain_provider" => {
          "cloudflare" => {
            "api_token" => "cf-token",
            "account_id" => "cf-account-id"
          }
        },
        "compute_provider" => {
          "aws" => {
            "access_key_id" => "aws-key",
            "secret_access_key" => "aws-secret",
            "region" => "us-east-1",
            "instance_type" => "t3.micro"
          }
        },
        "servers" => {
          "master" => { "master" => true }
        },
        "app" => {}
      }
    }

    deploy = Nvoi::Objects::DeployConfig.new(data)
    config = Nvoi::Objects::Configuration.new(deploy)

    assert_equal "aws", config.provider_name
  end

  def test_provider_name_returns_scaleway
    data = {
      "application" => {
        "name" => "myapp",
        "domain_provider" => {
          "cloudflare" => {
            "api_token" => "cf-token",
            "account_id" => "cf-account-id"
          }
        },
        "compute_provider" => {
          "scaleway" => {
            "secret_key" => "scw-secret",
            "project_id" => "scw-project",
            "server_type" => "DEV1-S"
          }
        },
        "servers" => {
          "master" => { "master" => true }
        },
        "app" => {}
      }
    }

    deploy = Nvoi::Objects::DeployConfig.new(data)
    config = Nvoi::Objects::Configuration.new(deploy)

    assert_equal "scaleway", config.provider_name
  end

  def test_keep_count_value_returns_default_when_nil
    deploy = Nvoi::Objects::DeployConfig.new(minimal_hetzner_config_data)
    config = Nvoi::Objects::Configuration.new(deploy)

    assert_equal 2, config.keep_count_value
  end

  def test_keep_count_value_returns_configured_value
    data = minimal_hetzner_config_data
    data["application"]["keep_count"] = 5

    deploy = Nvoi::Objects::DeployConfig.new(data)
    config = Nvoi::Objects::Configuration.new(deploy)

    assert_equal 5, config.keep_count_value
  end

  def test_hetzner_accessor
    deploy = Nvoi::Objects::DeployConfig.new(minimal_hetzner_config_data)
    config = Nvoi::Objects::Configuration.new(deploy)

    assert_equal "hz-token", config.hetzner.api_token
    assert_equal "cpx11", config.hetzner.server_type
  end

  def test_cloudflare_accessor
    deploy = Nvoi::Objects::DeployConfig.new(minimal_hetzner_config_data)
    config = Nvoi::Objects::Configuration.new(deploy)

    assert_equal "cf-token", config.cloudflare.api_token
    assert_equal "cf-account-id", config.cloudflare.account_id
  end

  def test_namer_is_lazily_created
    deploy = Nvoi::Objects::DeployConfig.new(minimal_hetzner_config_data)
    config = Nvoi::Objects::Configuration.new(deploy)

    namer = config.namer
    assert_instance_of Nvoi::Utils::Namer, namer
    assert_same namer, config.namer # Same instance returned
  end

  def test_validate_config_requires_cloudflare
    data = {
      "application" => {
        "name" => "myapp",
        "domain_provider" => {},
        "compute_provider" => {
          "hetzner" => {
            "api_token" => "hz-token",
            "server_type" => "cpx11",
            "server_location" => "fsn1"
          }
        },
        "servers" => { "master" => { "master" => true } },
        "app" => {}
      }
    }

    deploy = Nvoi::Objects::DeployConfig.new(data)
    config = Nvoi::Objects::Configuration.new(deploy)

    assert_raises(Nvoi::ConfigValidationError) do
      config.validate_config
    end
  end

  def test_validate_config_requires_compute_provider
    data = {
      "application" => {
        "name" => "myapp",
        "domain_provider" => {
          "cloudflare" => {
            "api_token" => "cf-token",
            "account_id" => "cf-account-id"
          }
        },
        "compute_provider" => {},
        "servers" => { "master" => { "master" => true } },
        "app" => {}
      }
    }

    deploy = Nvoi::Objects::DeployConfig.new(data)
    config = Nvoi::Objects::Configuration.new(deploy)

    assert_raises(Nvoi::ConfigValidationError) do
      config.validate_config
    end
  end

  def test_validate_config_passes_with_valid_config
    deploy = Nvoi::Objects::DeployConfig.new(minimal_hetzner_config_data)
    config = Nvoi::Objects::Configuration.new(deploy)

    # Should not raise
    config.validate_config
  end

  def test_validate_config_requires_exactly_one_master_with_multiple_servers
    data = minimal_hetzner_config_data
    data["application"]["servers"] = {
      "server1" => {},
      "server2" => {}
    }
    data["application"]["app"] = {}

    deploy = Nvoi::Objects::DeployConfig.new(data)
    config = Nvoi::Objects::Configuration.new(deploy)

    error = assert_raises(Nvoi::ConfigValidationError) do
      config.validate_config
    end
    assert_match(/exactly one must have master: true/, error.message)
  end

  def test_validate_config_validates_service_server_references
    data = minimal_hetzner_config_data
    data["application"]["app"] = {
      "web" => {
        "servers" => ["nonexistent"]
      }
    }

    deploy = Nvoi::Objects::DeployConfig.new(data)
    config = Nvoi::Objects::Configuration.new(deploy)

    error = assert_raises(Nvoi::ConfigValidationError) do
      config.validate_config
    end
    assert_match(/references undefined server/, error.message)
  end
end

class DeployConfigTest < Minitest::Test
  def test_initializes_with_empty_data
    config = Nvoi::Objects::DeployConfig.new({})

    assert_instance_of Nvoi::Objects::Application, config.application
    assert_nil config.application.name
  end

  def test_initializes_application
    data = {
      "application" => {
        "name" => "test-app",
        "environment" => "staging"
      }
    }

    config = Nvoi::Objects::DeployConfig.new(data)

    assert_equal "test-app", config.application.name
    assert_equal "staging", config.application.environment
  end
end

class ApplicationTest < Minitest::Test
  def test_defaults
    app = Nvoi::Objects::Application.new({})

    assert_nil app.name
    assert_equal "production", app.environment
    assert_equal({}, app.servers)
    assert_equal({}, app.app)
    assert_nil app.database
    assert_equal({}, app.services)
    assert_equal({}, app.env)
    assert_equal({}, app.secrets)
  end

  def test_parses_servers
    data = {
      "servers" => {
        "master" => { "master" => true, "type" => "cpx11" },
        "worker" => { "count" => 2 }
      }
    }

    app = Nvoi::Objects::Application.new(data)

    assert_equal 2, app.servers.size
    assert_equal true, app.servers["master"].master
    assert_equal "cpx11", app.servers["master"].type
    assert_equal 2, app.servers["worker"].count
  end

  def test_parses_app_services
    data = {
      "app" => {
        "web" => {
          "servers" => ["master"],
          "port" => 3000,
          "domain" => "example.com"
        }
      }
    }

    app = Nvoi::Objects::Application.new(data)

    assert_equal 1, app.app.size
    assert_equal ["master"], app.app["web"].servers
    assert_equal 3000, app.app["web"].port
    assert_equal "example.com", app.app["web"].domain
  end

  def test_parses_database
    data = {
      "database" => {
        "servers" => ["master"],
        "adapter" => "postgres",
        "secrets" => {
          "POSTGRES_USER" => "admin",
          "POSTGRES_PASSWORD" => "secret",
          "POSTGRES_DB" => "mydb"
        }
      }
    }

    app = Nvoi::Objects::Application.new(data)

    assert_instance_of Nvoi::Objects::DatabaseConfig, app.database
    assert_equal "postgres", app.database.adapter
    assert_equal "admin", app.database.secrets["POSTGRES_USER"]
  end
end

class ServerConfigTest < Minitest::Test
  def test_defaults
    config = Nvoi::Objects::ServerConfig.new({})

    assert_equal false, config.master
    assert_nil config.type
    assert_nil config.location
    assert_equal 1, config.count
    assert_equal({}, config.volumes)
  end

  def test_parses_volumes
    data = {
      "volumes" => {
        "data" => { "size" => 50 }
      }
    }

    config = Nvoi::Objects::ServerConfig.new(data)

    assert_equal 1, config.volumes.size
    assert_equal 50, config.volumes["data"].size
  end
end

class DatabaseConfigTest < Minitest::Test
  def test_to_service_spec_returns_nil_for_sqlite
    config = Nvoi::Objects::DatabaseConfig.new({
      "adapter" => "sqlite3"
    })

    mock_namer = Minitest::Mock.new
    result = config.to_service_spec(mock_namer)

    assert_nil result
  end

  def test_to_service_spec_creates_spec_for_postgres
    config = Nvoi::Objects::DatabaseConfig.new({
      "servers" => ["master"],
      "adapter" => "postgres",
      "secrets" => { "POSTGRES_USER" => "admin" }
    })

    mock_namer = Minitest::Mock.new
    mock_namer.expect(:database_service_name, "myapp-postgres")

    spec = config.to_service_spec(mock_namer)

    assert_equal "myapp-postgres", spec.name
    assert_equal 5432, spec.port
    assert_equal true, spec.stateful_set
    mock_namer.verify
  end

  def test_to_service_spec_creates_spec_for_mysql
    config = Nvoi::Objects::DatabaseConfig.new({
      "servers" => ["master"],
      "adapter" => "mysql",
      "secrets" => {}
    })

    mock_namer = Minitest::Mock.new
    mock_namer.expect(:database_service_name, "myapp-mysql")

    spec = config.to_service_spec(mock_namer)

    assert_equal "myapp-mysql", spec.name
    assert_equal 3306, spec.port
    mock_namer.verify
  end
end

class ServiceConfigTest < Minitest::Test
  def test_to_service_spec
    config = Nvoi::Objects::ServiceConfig.new({
      "servers" => ["master"],
      "image" => "redis:7",
      "port" => 6379
    })

    spec = config.to_service_spec("myapp", "cache")

    assert_equal "myapp-cache", spec.name
    assert_equal "redis:7", spec.image
    assert_equal 6379, spec.port
    assert_equal ["master"], spec.servers
  end

  def test_infers_port_from_redis_image
    config = Nvoi::Objects::ServiceConfig.new({
      "servers" => ["master"],
      "image" => "redis:latest"
    })

    spec = config.to_service_spec("myapp", "cache")

    assert_equal 6379, spec.port
  end

  def test_infers_port_from_postgres_image
    config = Nvoi::Objects::ServiceConfig.new({
      "servers" => ["master"],
      "image" => "postgres:15"
    })

    spec = config.to_service_spec("myapp", "db")

    assert_equal 5432, spec.port
  end
end

class ScalewayConfigTest < Minitest::Test
  def test_defaults_zone_to_fr_par_1
    config = Nvoi::Objects::ScalewayConfig.new({
      "secret_key" => "key",
      "project_id" => "proj"
    })

    assert_equal "fr-par-1", config.zone
  end

  def test_uses_provided_zone
    config = Nvoi::Objects::ScalewayConfig.new({
      "secret_key" => "key",
      "project_id" => "proj",
      "zone" => "nl-ams-1"
    })

    assert_equal "nl-ams-1", config.zone
  end
end
