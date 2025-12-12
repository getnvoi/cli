# frozen_string_literal: true

module Nvoi
  module ConfigApi
    module Actions
      class SetVolume < Base
        protected

          def mutate(data, server:, name:, size: 10)
            raise ArgumentError, "server is required" if server.nil? || server.to_s.empty?
            raise ArgumentError, "name is required" if name.nil? || name.to_s.empty?
            raise ArgumentError, "size must be positive" if size && size < 1

            servers = app(data)["servers"] ||= {}
            raise Errors::ConfigValidationError, "server '#{server}' not found" unless servers.key?(server.to_s)

            servers[server.to_s]["volumes"] ||= {}
            servers[server.to_s]["volumes"][name.to_s] = { "size" => size }
          end
      end

      class DeleteVolume < Base
        protected

          def mutate(data, server:, name:)
            raise ArgumentError, "server is required" if server.nil? || server.to_s.empty?
            raise ArgumentError, "name is required" if name.nil? || name.to_s.empty?

            servers = app(data)["servers"] || {}
            raise Errors::ConfigValidationError, "server '#{server}' not found" unless servers.key?(server.to_s)

            volumes = servers[server.to_s]["volumes"] || {}
            raise Errors::ConfigValidationError, "volume '#{name}' not found on server '#{server}'" unless volumes.key?(name.to_s)

            volumes.delete(name.to_s)
          end
      end
    end
  end
end
