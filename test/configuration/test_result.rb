# frozen_string_literal: true

require "test_helper"

class TestConfigurationResult < Minitest::Test
  def test_success_result
    result = Nvoi::Configuration::Result.success({ "foo" => "bar" })

    assert result.success?
    refute result.failure?
    assert_equal({ "foo" => "bar" }, result.data)
    assert_nil result.error_type
    assert_nil result.error_message
  end

  def test_failure_result
    result = Nvoi::Configuration::Result.failure(:validation_error, "something went wrong")

    refute result.success?
    assert result.failure?
    assert_nil result.data
    assert_equal :validation_error, result.error_type
    assert_equal "something went wrong", result.error_message
  end

  def test_init_result_success
    result = Nvoi::Configuration::InitResult.new(
      config: "encrypted_data",
      master_key: "key123",
      ssh_public_key: "ssh-ed25519 AAA..."
    )

    assert result.success?
    refute result.failure?
    assert_equal "encrypted_data", result.config
    assert_equal "key123", result.master_key
    assert_equal "ssh-ed25519 AAA...", result.ssh_public_key
  end

  def test_init_result_failure
    result = Nvoi::Configuration::InitResult.new(
      error_type: :invalid_args,
      error_message: "name is required"
    )

    refute result.success?
    assert result.failure?
    assert_nil result.config
    assert_equal :invalid_args, result.error_type
    assert_equal "name is required", result.error_message
  end
end
