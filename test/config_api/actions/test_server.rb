# frozen_string_literal: true

require "test_helper"

class TestServerActions < Minitest::Test
  def setup
    @base_config = { "application" => { "name" => "test" } }
  end

  # SetServer

  def test_set_server_minimal
    result = Nvoi::ConfigApi.set_server(@base_config, name: "web")

    assert result.success?

    assert result.data["application"]["servers"].key?("web")
    assert_equal false, result.data["application"]["servers"]["web"]["master"]
    assert_equal 1, result.data["application"]["servers"]["web"]["count"]
  end

  def test_set_server_with_all_options
    result = Nvoi::ConfigApi.set_server(
      @base_config,
      name: "workers",
      master: true,
      type: "cx32",
      location: "nbg1",
      count: 3
    )

    assert result.success?

    server = result.data["application"]["servers"]["workers"]
    assert_equal true, server["master"]
    assert_equal "cx32", server["type"]
    assert_equal "nbg1", server["location"]
    assert_equal 3, server["count"]
  end

  def test_set_server_updates_existing
    config = { "application" => { "servers" => { "web" => { "count" => 1 } } } }

    result = Nvoi::ConfigApi.set_server(config, name: "web", count: 5)

    assert result.success?
    assert_equal 5, result.data["application"]["servers"]["web"]["count"]
  end

  def test_set_server_fails_without_name
    result = Nvoi::ConfigApi.set_server(@base_config)

    assert result.failure?
    assert_equal :invalid_args, result.error_type
    assert_match(/name/, result.error_message)
  end

  def test_set_server_fails_with_empty_name
    result = Nvoi::ConfigApi.set_server(@base_config, name: "")

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  def test_set_server_fails_with_invalid_count
    result = Nvoi::ConfigApi.set_server(@base_config, name: "web", count: 0)

    assert result.failure?
    assert_equal :invalid_args, result.error_type
    assert_match(/count must be positive/, result.error_message)
  end

  # DeleteServer

  def test_delete_server
    config = { "application" => { "servers" => { "web" => {}, "workers" => {} } } }

    result = Nvoi::ConfigApi.delete_server(config, name: "workers")

    assert result.success?
    assert result.data["application"]["servers"].key?("web")
    refute result.data["application"]["servers"].key?("workers")
  end

  def test_delete_server_fails_if_not_found
    result = Nvoi::ConfigApi.delete_server(@base_config, name: "nonexistent")

    assert result.failure?
    assert_equal :validation_error, result.error_type
    assert_match(/not found/, result.error_message)
  end

  def test_delete_server_fails_if_referenced_by_app
    config = {
      "application" => {
        "servers" => { "web" => {} },
        "app" => { "api" => { "servers" => ["web"] } }
      }
    }

    result = Nvoi::ConfigApi.delete_server(config, name: "web")

    assert result.failure?
    assert_equal :validation_error, result.error_type
    assert_match(/app\.api references/, result.error_message)
  end

  def test_delete_server_fails_if_referenced_by_database
    config = {
      "application" => {
        "servers" => { "db" => {} },
        "database" => { "servers" => ["db"], "adapter" => "postgres" }
      }
    }

    result = Nvoi::ConfigApi.delete_server(config, name: "db")

    assert result.failure?
    assert_equal :validation_error, result.error_type
    assert_match(/database references/, result.error_message)
  end

  def test_delete_server_fails_if_referenced_by_service
    config = {
      "application" => {
        "servers" => { "cache" => {} },
        "services" => { "redis" => { "servers" => ["cache"] } }
      }
    }

    result = Nvoi::ConfigApi.delete_server(config, name: "cache")

    assert result.failure?
    assert_equal :validation_error, result.error_type
    assert_match(/services\.redis references/, result.error_message)
  end
end
