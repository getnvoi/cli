# frozen_string_literal: true

module Nvoi
  module ConfigApi
    # Base class for config transformations.
    # Accepts a Hash, returns a Hash. No crypto - caller handles that.
    class Base
      def initialize(data)
        @data = data
      end

      def call(**args)
        mutate(@data, **args)
        validate(@data)
        Result.success(@data)
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
