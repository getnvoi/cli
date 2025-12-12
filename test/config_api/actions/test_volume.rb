# frozen_string_literal: true

require "test_helper"

class TestVolumeActions < Minitest::Test
  def setup
    @config_with_server = { "application" => { "servers" => { "web" => {} } } }
  end

  # SetVolume

  def test_set_volume_with_default_size
    result = Nvoi::ConfigApi.set_volume(@config_with_server, server: "web", name: "data")

    assert result.success?
    assert_equal 10, result.data["application"]["servers"]["web"]["volumes"]["data"]["size"]
  end

  def test_set_volume_with_custom_size
    result = Nvoi::ConfigApi.set_volume(@config_with_server, server: "web", name: "data", size: 100)

    assert result.success?
    assert_equal 100, result.data["application"]["servers"]["web"]["volumes"]["data"]["size"]
  end

  def test_set_volume_updates_existing
    config = {
      "application" => {
        "servers" => { "web" => { "volumes" => { "data" => { "size" => 10 } } } }
      }
    }

    result = Nvoi::ConfigApi.set_volume(config, server: "web", name: "data", size: 50)

    assert result.success?
    assert_equal 50, result.data["application"]["servers"]["web"]["volumes"]["data"]["size"]
  end

  def test_set_volume_fails_without_server
    result = Nvoi::ConfigApi.set_volume(@config_with_server, name: "data")

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  def test_set_volume_fails_without_name
    result = Nvoi::ConfigApi.set_volume(@config_with_server, server: "web")

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  def test_set_volume_fails_if_server_not_found
    result = Nvoi::ConfigApi.set_volume(@config_with_server, server: "nonexistent", name: "data")

    assert result.failure?
    assert_equal :validation_error, result.error_type
    assert_match(/server .* not found/, result.error_message)
  end

  def test_set_volume_fails_with_invalid_size
    result = Nvoi::ConfigApi.set_volume(@config_with_server, server: "web", name: "data", size: 0)

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

    result = Nvoi::ConfigApi.delete_volume(config, server: "web", name: "data")

    assert result.success?
    refute result.data["application"]["servers"]["web"]["volumes"].key?("data")
    assert result.data["application"]["servers"]["web"]["volumes"].key?("logs")
  end

  def test_delete_volume_fails_if_server_not_found
    result = Nvoi::ConfigApi.delete_volume(@config_with_server, server: "nonexistent", name: "data")

    assert result.failure?
    assert_equal :validation_error, result.error_type
  end

  def test_delete_volume_fails_if_volume_not_found
    result = Nvoi::ConfigApi.delete_volume(@config_with_server, server: "web", name: "nonexistent")

    assert result.failure?
    assert_equal :validation_error, result.error_type
    assert_match(/volume .* not found/, result.error_message)
  end
end
