# frozen_string_literal: true

require "test_helper"

class TestConfigApiBase < Minitest::Test
  def setup
    @master_key = Nvoi::Utils::Crypto.generate_key
    @valid_config = {
      "application" => {
        "name" => "test-app",
        "servers" => { "master" => { "master" => true } }
      }
    }
    @encrypted = Nvoi::Utils::Crypto.encrypt(YAML.dump(@valid_config), @master_key)
  end

  def test_decrypt_failure_with_wrong_key
    wrong_key = Nvoi::Utils::Crypto.generate_key
    action = NoOpAction.new(@encrypted, wrong_key)
    result = action.call

    assert result.failure?
    assert_equal :decryption_error, result.error_type
  end

  def test_decrypt_failure_with_invalid_key_format
    action = NoOpAction.new(@encrypted, "not-a-valid-key")
    result = action.call

    assert result.failure?
    assert_equal :decryption_error, result.error_type
  end

  def test_returns_encrypted_config_on_success
    action = NoOpAction.new(@encrypted, @master_key)
    result = action.call

    assert result.success?
    assert_instance_of String, result.config

    # Verify can decrypt result
    decrypted = Nvoi::Utils::Crypto.decrypt(result.config, @master_key)
    data = YAML.safe_load(decrypted)
    assert_equal "test-app", data["application"]["name"]
  end

  def test_validation_error_returns_failure
    action = FailingValidationAction.new(@encrypted, @master_key)
    result = action.call

    assert result.failure?
    assert_equal :validation_error, result.error_type
    assert_match(/validation failed/, result.error_message)
  end

  def test_argument_error_returns_failure
    action = FailingArgsAction.new(@encrypted, @master_key)
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
