# frozen_string_literal: true

module Nvoi
  module ConfigApi
    module Actions
      class SetSecret < Base
        protected

        def mutate(data, key:, value:)
          raise ArgumentError, "key is required" if key.nil? || key.to_s.empty?
          raise ArgumentError, "value is required" if value.nil?

          app(data)["secrets"] ||= {}
          app(data)["secrets"][key.to_s] = value.to_s
        end
      end

      class DeleteSecret < Base
        protected

        def mutate(data, key:)
          raise ArgumentError, "key is required" if key.nil? || key.to_s.empty?

          secrets = app(data)["secrets"] || {}
          raise Errors::ConfigValidationError, "secret '#{key}' not found" unless secrets.key?(key.to_s)

          secrets.delete(key.to_s)
        end
      end
    end
  end
end
