# frozen_string_literal: true

require "test_helper"

class TestConfigApiResult < Minitest::Test
  def test_success_result
    result = Nvoi::ConfigApi::Result.success("encrypted_data")

    assert result.success?
    refute result.failure?
    assert_equal "encrypted_data", result.config
    assert_nil result.error_type
    assert_nil result.error_message
  end

  def test_failure_result
    result = Nvoi::ConfigApi::Result.failure(:validation_error, "name required")

    refute result.success?
    assert result.failure?
    assert_nil result.config
    assert_equal :validation_error, result.error_type
    assert_equal "name required", result.error_message
  end
end
