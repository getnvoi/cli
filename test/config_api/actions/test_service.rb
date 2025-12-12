# frozen_string_literal: true

require "test_helper"

class TestServiceActions < Minitest::Test
  def setup
    @config_with_server = { "application" => { "servers" => { "web" => {}, "cache" => {} } } }
  end

  # SetService

  def test_set_service_minimal
    result = Nvoi::ConfigApi.set_service(
      @config_with_server,
      name: "redis",
      servers: ["web"],
      image: "redis:7-alpine"
    )

    assert result.success?
    assert result.data["application"]["services"].key?("redis")
    assert_equal ["web"], result.data["application"]["services"]["redis"]["servers"]
    assert_equal "redis:7-alpine", result.data["application"]["services"]["redis"]["image"]
  end

  def test_set_service_with_all_options
    result = Nvoi::ConfigApi.set_service(
      @config_with_server,
      name: "redis",
      servers: ["web", "cache"],
      image: "redis:7-alpine",
      port: 6379,
      command: "redis-server --appendonly yes",
      env: { "REDIS_PASSWORD" => "secret" },
      mount: { "data" => "/data" }
    )

    assert result.success?

    svc = result.data["application"]["services"]["redis"]
    assert_equal ["web", "cache"], svc["servers"]
    assert_equal "redis:7-alpine", svc["image"]
    assert_equal 6379, svc["port"]
    assert_equal "redis-server --appendonly yes", svc["command"]
    assert_equal({ "REDIS_PASSWORD" => "secret" }, svc["env"])
    assert_equal({ "data" => "/data" }, svc["mount"])
  end

  def test_set_service_updates_existing
    config = {
      "application" => {
        "servers" => { "web" => {} },
        "services" => { "redis" => { "servers" => ["web"], "image" => "redis:6" } }
      }
    }

    result = Nvoi::ConfigApi.set_service(
      config,
      name: "redis",
      servers: ["web"],
      image: "redis:7-alpine"
    )

    assert result.success?
    assert_equal "redis:7-alpine", result.data["application"]["services"]["redis"]["image"]
  end

  def test_set_service_fails_without_name
    result = Nvoi::ConfigApi.set_service(@config_with_server, servers: ["web"], image: "redis")

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  def test_set_service_fails_without_servers
    result = Nvoi::ConfigApi.set_service(@config_with_server, name: "redis", image: "redis")

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  def test_set_service_fails_without_image
    result = Nvoi::ConfigApi.set_service(@config_with_server, name: "redis", servers: ["web"])

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  def test_set_service_fails_if_server_not_found
    result = Nvoi::ConfigApi.set_service(
      @config_with_server,
      name: "redis",
      servers: ["nonexistent"],
      image: "redis"
    )

    assert result.failure?
    assert_equal :validation_error, result.error_type
    assert_match(/server .* not found/, result.error_message)
  end

  # DeleteService

  def test_delete_service
    config = {
      "application" => {
        "servers" => { "web" => {} },
        "services" => { "redis" => { "servers" => ["web"], "image" => "redis" }, "memcached" => { "servers" => ["web"], "image" => "memcached" } }
      }
    }

    result = Nvoi::ConfigApi.delete_service(config, name: "redis")

    assert result.success?
    refute result.data["application"]["services"].key?("redis")
    assert result.data["application"]["services"].key?("memcached")
  end

  def test_delete_service_fails_if_not_found
    result = Nvoi::ConfigApi.delete_service(@config_with_server, name: "nonexistent")

    assert result.failure?
    assert_equal :validation_error, result.error_type
    assert_match(/not found/, result.error_message)
  end
end
