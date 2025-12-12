# frozen_string_literal: true

module Nvoi
  module ConfigApi
    module Actions
      class SetService < Base
        protected

        def mutate(data, name:, servers:, image:, port: nil, command: nil, env: nil, mount: nil)
          raise ArgumentError, "name is required" if name.nil? || name.to_s.empty?
          raise ArgumentError, "servers is required" if servers.nil? || servers.empty?
          raise ArgumentError, "servers must be an array" unless servers.is_a?(Array)
          raise ArgumentError, "image is required" if image.nil? || image.to_s.empty?

          validate_server_refs(data, servers)

          app(data)["services"] ||= {}
          app(data)["services"][name.to_s] = {
            "servers" => servers.map(&:to_s),
            "image" => image.to_s,
            "port" => port,
            "command" => command,
            "env" => env,
            "mount" => mount
          }.compact
        end

        private

        def validate_server_refs(data, servers)
          defined = (app(data)["servers"] || {}).keys
          servers.each do |ref|
            raise Errors::ConfigValidationError, "server '#{ref}' not found" unless defined.include?(ref.to_s)
          end
        end
      end

      class DeleteService < Base
        protected

        def mutate(data, name:)
          raise ArgumentError, "name is required" if name.nil? || name.to_s.empty?

          services = app(data)["services"] || {}
          raise Errors::ConfigValidationError, "service '#{name}' not found" unless services.key?(name.to_s)

          services.delete(name.to_s)
        end
      end
    end
  end
end
