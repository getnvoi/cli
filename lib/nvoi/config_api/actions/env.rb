# frozen_string_literal: true

module Nvoi
  module ConfigApi
    module Actions
      class SetEnv < Base
        protected

          def mutate(data, key:, value:)
            raise ArgumentError, "key is required" if key.nil? || key.to_s.empty?
            raise ArgumentError, "value is required" if value.nil?

            app(data)["env"] ||= {}
            app(data)["env"][key.to_s] = value.to_s
          end
      end

      class DeleteEnv < Base
        protected

          def mutate(data, key:)
            raise ArgumentError, "key is required" if key.nil? || key.to_s.empty?

            env = app(data)["env"] || {}
            raise Errors::ConfigValidationError, "env '#{key}' not found" unless env.key?(key.to_s)

            env.delete(key.to_s)
          end
      end
    end
  end
end
