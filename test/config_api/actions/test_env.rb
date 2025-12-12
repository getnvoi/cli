# frozen_string_literal: true

require "test_helper"

class TestEnvActions < Minitest::Test
  def setup
    @master_key = Nvoi::Utils::Crypto.generate_key
    @base_config = { "application" => { "name" => "test" } }
    @encrypted = encrypt(@base_config)
  end

  # SetEnv

  def test_set_env
    result = Nvoi::ConfigApi.set_env(@encrypted, @master_key, key: "RAILS_ENV", value: "production")

    assert result.success?
    data = decrypt(result.config)

    assert_equal "production", data["application"]["env"]["RAILS_ENV"]
  end

  def test_set_env_updates_existing
    config = { "application" => { "env" => { "RAILS_ENV" => "development" } } }
    encrypted = encrypt(config)

    result = Nvoi::ConfigApi.set_env(encrypted, @master_key, key: "RAILS_ENV", value: "production")

    assert result.success?
    data = decrypt(result.config)

    assert_equal "production", data["application"]["env"]["RAILS_ENV"]
  end

  def test_set_env_preserves_other_vars
    config = { "application" => { "env" => { "EXISTING" => "value" } } }
    encrypted = encrypt(config)

    result = Nvoi::ConfigApi.set_env(encrypted, @master_key, key: "NEW_VAR", value: "new_value")

    assert result.success?
    data = decrypt(result.config)

    assert_equal "value", data["application"]["env"]["EXISTING"]
    assert_equal "new_value", data["application"]["env"]["NEW_VAR"]
  end

  def test_set_env_fails_without_key
    result = Nvoi::ConfigApi.set_env(@encrypted, @master_key, value: "val")

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  def test_set_env_fails_without_value
    result = Nvoi::ConfigApi.set_env(@encrypted, @master_key, key: "KEY")

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  # DeleteEnv

  def test_delete_env
    config = { "application" => { "env" => { "RAILS_ENV" => "prod", "OTHER" => "val" } } }
    encrypted = encrypt(config)

    result = Nvoi::ConfigApi.delete_env(encrypted, @master_key, key: "RAILS_ENV")

    assert result.success?
    data = decrypt(result.config)

    refute data["application"]["env"].key?("RAILS_ENV")
    assert data["application"]["env"].key?("OTHER")
  end

  def test_delete_env_fails_if_not_found
    result = Nvoi::ConfigApi.delete_env(@encrypted, @master_key, key: "NONEXISTENT")

    assert result.failure?
    assert_equal :validation_error, result.error_type
    assert_match(/not found/, result.error_message)
  end

  private

  def encrypt(data)
    Nvoi::Utils::Crypto.encrypt(YAML.dump(data), @master_key)
  end

  def decrypt(encrypted)
    YAML.safe_load(Nvoi::Utils::Crypto.decrypt(encrypted, @master_key))
  end
end
