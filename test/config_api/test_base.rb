# frozen_string_literal: true

require "test_helper"

class TestConfigApiBase < Minitest::Test
  def setup
    @valid_config = {
      "application" => {
        "name" => "test-app",
        "servers" => { "master" => { "master" => true } }
      }
    }
  end

  def test_returns_data_on_success
    action = NoOpAction.new(@valid_config)
    result = action.call

    assert result.success?
    assert_instance_of Hash, result.data
    assert_equal "test-app", result.data["application"]["name"]
  end

  def test_validation_error_returns_failure
    action = FailingValidationAction.new(@valid_config)
    result = action.call

    assert result.failure?
    assert_equal :validation_error, result.error_type
    assert_match(/validation failed/, result.error_message)
  end

  def test_argument_error_returns_failure
    action = FailingArgsAction.new(@valid_config)
    result = action.call

    assert result.failure?
    assert_equal :invalid_args, result.error_type
    assert_match(/bad argument/, result.error_message)
  end

  # Test helper actions
  class NoOpAction < Nvoi::ConfigApi::Base
    def mutate(_data, **_args)
      # no-op
    end
  end

  class FailingValidationAction < Nvoi::ConfigApi::Base
    def mutate(_data, **_args)
      # no-op
    end

    def validate(_data)
      raise Nvoi::Errors::ConfigValidationError, "validation failed"
    end
  end

  class FailingArgsAction < Nvoi::ConfigApi::Base
    def mutate(_data, **_args)
      raise ArgumentError, "bad argument"
    end
  end
end
