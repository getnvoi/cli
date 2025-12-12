# frozen_string_literal: true

require "test_helper"

class TestSecretActions < Minitest::Test
  def setup
    @base_config = { "application" => { "name" => "test" } }
  end

  # SetSecret

  def test_set_secret
    result = Nvoi::ConfigApi.set_secret(@base_config, key: "API_KEY", value: "secret123")

    assert result.success?
    assert_equal "secret123", result.data["application"]["secrets"]["API_KEY"]
  end

  def test_set_secret_updates_existing
    config = { "application" => { "secrets" => { "API_KEY" => "old" } } }

    result = Nvoi::ConfigApi.set_secret(config, key: "API_KEY", value: "new")

    assert result.success?
    assert_equal "new", result.data["application"]["secrets"]["API_KEY"]
  end

  def test_set_secret_preserves_other_secrets
    config = { "application" => { "secrets" => { "EXISTING" => "value" } } }

    result = Nvoi::ConfigApi.set_secret(config, key: "NEW_KEY", value: "new_value")

    assert result.success?
    assert_equal "value", result.data["application"]["secrets"]["EXISTING"]
    assert_equal "new_value", result.data["application"]["secrets"]["NEW_KEY"]
  end

  def test_set_secret_fails_without_key
    result = Nvoi::ConfigApi.set_secret(@base_config, value: "val")

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  def test_set_secret_fails_without_value
    result = Nvoi::ConfigApi.set_secret(@base_config, key: "KEY")

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  # DeleteSecret

  def test_delete_secret
    config = { "application" => { "secrets" => { "API_KEY" => "secret", "OTHER" => "val" } } }

    result = Nvoi::ConfigApi.delete_secret(config, key: "API_KEY")

    assert result.success?
    refute result.data["application"]["secrets"].key?("API_KEY")
    assert result.data["application"]["secrets"].key?("OTHER")
  end

  def test_delete_secret_fails_if_not_found
    result = Nvoi::ConfigApi.delete_secret(@base_config, key: "NONEXISTENT")

    assert result.failure?
    assert_equal :validation_error, result.error_type
    assert_match(/not found/, result.error_message)
  end
end
