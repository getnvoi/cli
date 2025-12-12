# frozen_string_literal: true

require "test_helper"

class TestSecretActions < Minitest::Test
  def setup
    @master_key = Nvoi::Utils::Crypto.generate_key
    @base_config = { "application" => { "name" => "test" } }
    @encrypted = encrypt(@base_config)
  end

  # SetSecret

  def test_set_secret
    result = Nvoi::ConfigApi.set_secret(@encrypted, @master_key, key: "API_KEY", value: "secret123")

    assert result.success?
    data = decrypt(result.config)

    assert_equal "secret123", data["application"]["secrets"]["API_KEY"]
  end

  def test_set_secret_updates_existing
    config = { "application" => { "secrets" => { "API_KEY" => "old" } } }
    encrypted = encrypt(config)

    result = Nvoi::ConfigApi.set_secret(encrypted, @master_key, key: "API_KEY", value: "new")

    assert result.success?
    data = decrypt(result.config)

    assert_equal "new", data["application"]["secrets"]["API_KEY"]
  end

  def test_set_secret_preserves_other_secrets
    config = { "application" => { "secrets" => { "EXISTING" => "value" } } }
    encrypted = encrypt(config)

    result = Nvoi::ConfigApi.set_secret(encrypted, @master_key, key: "NEW_KEY", value: "new_value")

    assert result.success?
    data = decrypt(result.config)

    assert_equal "value", data["application"]["secrets"]["EXISTING"]
    assert_equal "new_value", data["application"]["secrets"]["NEW_KEY"]
  end

  def test_set_secret_fails_without_key
    result = Nvoi::ConfigApi.set_secret(@encrypted, @master_key, value: "val")

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  def test_set_secret_fails_without_value
    result = Nvoi::ConfigApi.set_secret(@encrypted, @master_key, key: "KEY")

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  # DeleteSecret

  def test_delete_secret
    config = { "application" => { "secrets" => { "API_KEY" => "secret", "OTHER" => "val" } } }
    encrypted = encrypt(config)

    result = Nvoi::ConfigApi.delete_secret(encrypted, @master_key, key: "API_KEY")

    assert result.success?
    data = decrypt(result.config)

    refute data["application"]["secrets"].key?("API_KEY")
    assert data["application"]["secrets"].key?("OTHER")
  end

  def test_delete_secret_fails_if_not_found
    result = Nvoi::ConfigApi.delete_secret(@encrypted, @master_key, key: "NONEXISTENT")

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
