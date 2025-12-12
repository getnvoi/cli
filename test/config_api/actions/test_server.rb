# frozen_string_literal: true

require "test_helper"

class TestServerActions < Minitest::Test
  def setup
    @master_key = Nvoi::Utils::Crypto.generate_key
    @base_config = { "application" => { "name" => "test" } }
    @encrypted = encrypt(@base_config)
  end

  # SetServer

  def test_set_server_minimal
    result = Nvoi::ConfigApi.set_server(@encrypted, @master_key, name: "web")

    assert result.success?
    data = decrypt(result.config)

    assert data["application"]["servers"].key?("web")
    assert_equal false, data["application"]["servers"]["web"]["master"]
    assert_equal 1, data["application"]["servers"]["web"]["count"]
  end

  def test_set_server_with_all_options
    result = Nvoi::ConfigApi.set_server(
      @encrypted, @master_key,
      name: "workers",
      master: true,
      type: "cx32",
      location: "nbg1",
      count: 3
    )

    assert result.success?
    data = decrypt(result.config)

    server = data["application"]["servers"]["workers"]
    assert_equal true, server["master"]
    assert_equal "cx32", server["type"]
    assert_equal "nbg1", server["location"]
    assert_equal 3, server["count"]
  end

  def test_set_server_updates_existing
    config = { "application" => { "servers" => { "web" => { "count" => 1 } } } }
    encrypted = encrypt(config)

    result = Nvoi::ConfigApi.set_server(encrypted, @master_key, name: "web", count: 5)

    assert result.success?
    data = decrypt(result.config)

    assert_equal 5, data["application"]["servers"]["web"]["count"]
  end

  def test_set_server_fails_without_name
    result = Nvoi::ConfigApi.set_server(@encrypted, @master_key)

    assert result.failure?
    assert_equal :invalid_args, result.error_type
    assert_match(/name is required/, result.error_message)
  end

  def test_set_server_fails_with_empty_name
    result = Nvoi::ConfigApi.set_server(@encrypted, @master_key, name: "")

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  def test_set_server_fails_with_invalid_count
    result = Nvoi::ConfigApi.set_server(@encrypted, @master_key, name: "web", count: 0)

    assert result.failure?
    assert_equal :invalid_args, result.error_type
    assert_match(/count must be positive/, result.error_message)
  end

  # DeleteServer

  def test_delete_server
    config = { "application" => { "servers" => { "web" => {}, "workers" => {} } } }
    encrypted = encrypt(config)

    result = Nvoi::ConfigApi.delete_server(encrypted, @master_key, name: "workers")

    assert result.success?
    data = decrypt(result.config)

    assert data["application"]["servers"].key?("web")
    refute data["application"]["servers"].key?("workers")
  end

  def test_delete_server_fails_if_not_found
    result = Nvoi::ConfigApi.delete_server(@encrypted, @master_key, name: "nonexistent")

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
    encrypted = encrypt(config)

    result = Nvoi::ConfigApi.delete_server(encrypted, @master_key, name: "web")

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
    encrypted = encrypt(config)

    result = Nvoi::ConfigApi.delete_server(encrypted, @master_key, name: "db")

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
    encrypted = encrypt(config)

    result = Nvoi::ConfigApi.delete_server(encrypted, @master_key, name: "cache")

    assert result.failure?
    assert_equal :validation_error, result.error_type
    assert_match(/services\.redis references/, result.error_message)
  end

  private

  def encrypt(data)
    Nvoi::Utils::Crypto.encrypt(YAML.dump(data), @master_key)
  end

  def decrypt(encrypted)
    YAML.safe_load(Nvoi::Utils::Crypto.decrypt(encrypted, @master_key))
  end
end
