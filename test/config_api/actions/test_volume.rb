# frozen_string_literal: true

require "test_helper"

class TestVolumeActions < Minitest::Test
  def setup
    @master_key = Nvoi::Utils::Crypto.generate_key
    @config_with_server = { "application" => { "servers" => { "web" => {} } } }
    @encrypted = encrypt(@config_with_server)
  end

  # SetVolume

  def test_set_volume_with_default_size
    result = Nvoi::ConfigApi.set_volume(@encrypted, @master_key, server: "web", name: "data")

    assert result.success?
    data = decrypt(result.config)

    assert_equal 10, data["application"]["servers"]["web"]["volumes"]["data"]["size"]
  end

  def test_set_volume_with_custom_size
    result = Nvoi::ConfigApi.set_volume(@encrypted, @master_key, server: "web", name: "data", size: 100)

    assert result.success?
    data = decrypt(result.config)

    assert_equal 100, data["application"]["servers"]["web"]["volumes"]["data"]["size"]
  end

  def test_set_volume_updates_existing
    config = {
      "application" => {
        "servers" => { "web" => { "volumes" => { "data" => { "size" => 10 } } } }
      }
    }
    encrypted = encrypt(config)

    result = Nvoi::ConfigApi.set_volume(encrypted, @master_key, server: "web", name: "data", size: 50)

    assert result.success?
    data = decrypt(result.config)

    assert_equal 50, data["application"]["servers"]["web"]["volumes"]["data"]["size"]
  end

  def test_set_volume_fails_without_server
    result = Nvoi::ConfigApi.set_volume(@encrypted, @master_key, name: "data")

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  def test_set_volume_fails_without_name
    result = Nvoi::ConfigApi.set_volume(@encrypted, @master_key, server: "web")

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  def test_set_volume_fails_if_server_not_found
    result = Nvoi::ConfigApi.set_volume(@encrypted, @master_key, server: "nonexistent", name: "data")

    assert result.failure?
    assert_equal :validation_error, result.error_type
    assert_match(/server .* not found/, result.error_message)
  end

  def test_set_volume_fails_with_invalid_size
    result = Nvoi::ConfigApi.set_volume(@encrypted, @master_key, server: "web", name: "data", size: 0)

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  # DeleteVolume

  def test_delete_volume
    config = {
      "application" => {
        "servers" => { "web" => { "volumes" => { "data" => { "size" => 10 }, "logs" => { "size" => 5 } } } }
      }
    }
    encrypted = encrypt(config)

    result = Nvoi::ConfigApi.delete_volume(encrypted, @master_key, server: "web", name: "data")

    assert result.success?
    data = decrypt(result.config)

    refute data["application"]["servers"]["web"]["volumes"].key?("data")
    assert data["application"]["servers"]["web"]["volumes"].key?("logs")
  end

  def test_delete_volume_fails_if_server_not_found
    result = Nvoi::ConfigApi.delete_volume(@encrypted, @master_key, server: "nonexistent", name: "data")

    assert result.failure?
    assert_equal :validation_error, result.error_type
  end

  def test_delete_volume_fails_if_volume_not_found
    result = Nvoi::ConfigApi.delete_volume(@encrypted, @master_key, server: "web", name: "nonexistent")

    assert result.failure?
    assert_equal :validation_error, result.error_type
    assert_match(/volume .* not found/, result.error_message)
  end

  private

  def encrypt(data)
    Nvoi::Utils::Crypto.encrypt(YAML.dump(data), @master_key)
  end

  def decrypt(encrypted)
    YAML.safe_load(Nvoi::Utils::Crypto.decrypt(encrypted, @master_key))
  end
end
