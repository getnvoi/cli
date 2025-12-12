# frozen_string_literal: true

require "test_helper"

class TestEnvActions < Minitest::Test
  def setup
    @base_config = { "application" => { "name" => "test" } }
  end

  # SetEnv

  def test_set_env
    result = Nvoi::ConfigApi.set_env(@base_config, key: "RAILS_ENV", value: "production")

    assert result.success?
    assert_equal "production", result.data["application"]["env"]["RAILS_ENV"]
  end

  def test_set_env_updates_existing
    config = { "application" => { "env" => { "RAILS_ENV" => "development" } } }

    result = Nvoi::ConfigApi.set_env(config, key: "RAILS_ENV", value: "production")

    assert result.success?
    assert_equal "production", result.data["application"]["env"]["RAILS_ENV"]
  end

  def test_set_env_preserves_other_vars
    config = { "application" => { "env" => { "EXISTING" => "value" } } }

    result = Nvoi::ConfigApi.set_env(config, key: "NEW_VAR", value: "new_value")

    assert result.success?
    assert_equal "value", result.data["application"]["env"]["EXISTING"]
    assert_equal "new_value", result.data["application"]["env"]["NEW_VAR"]
  end

  def test_set_env_fails_without_key
    result = Nvoi::ConfigApi.set_env(@base_config, value: "val")

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  def test_set_env_fails_without_value
    result = Nvoi::ConfigApi.set_env(@base_config, key: "KEY")

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  # DeleteEnv

  def test_delete_env
    config = { "application" => { "env" => { "RAILS_ENV" => "prod", "OTHER" => "val" } } }

    result = Nvoi::ConfigApi.delete_env(config, key: "RAILS_ENV")

    assert result.success?
    refute result.data["application"]["env"].key?("RAILS_ENV")
    assert result.data["application"]["env"].key?("OTHER")
  end

  def test_delete_env_fails_if_not_found
    result = Nvoi::ConfigApi.delete_env(@base_config, key: "NONEXISTENT")

    assert result.failure?
    assert_equal :validation_error, result.error_type
    assert_match(/not found/, result.error_message)
  end
end
