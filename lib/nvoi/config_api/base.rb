# frozen_string_literal: true

module Nvoi
  module ConfigApi
    class Base
      def initialize(encrypted_config, master_key)
        @encrypted_config = encrypted_config
        @master_key = master_key
      end

      def call(**args)
        yaml = Utils::Crypto.decrypt(@encrypted_config, @master_key)
        @data = YAML.safe_load(yaml, permitted_classes: [Symbol])

        mutate(@data, **args)
        validate(@data)

        new_yaml = YAML.dump(@data)
        Result.success(Utils::Crypto.encrypt(new_yaml, @master_key))
      rescue Errors::DecryptionError, Errors::InvalidKeyError => e
        Result.failure(:decryption_error, e.message)
      rescue Errors::ConfigValidationError => e
        Result.failure(:validation_error, e.message)
      rescue ArgumentError => e
        Result.failure(:invalid_args, e.message)
      end

      protected

      def mutate(_data, **_args)
        raise NotImplementedError
      end

      def validate(_data)
        # Subclasses can override to add validation
        # Default: no validation (lightweight actions like set_env don't need full config validation)
      end

      def app(data)
        data["application"] ||= {}
      end
    end
  end
end
