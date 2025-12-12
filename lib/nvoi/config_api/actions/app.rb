# frozen_string_literal: true

module Nvoi
  module ConfigApi
    module Actions
      class SetApp < Base
        protected

        def mutate(data, name:, servers:, domain: nil, subdomain: nil, port: nil, command: nil, pre_run_command: nil, env: nil, mounts: nil)
          raise ArgumentError, "name is required" if name.nil? || name.to_s.empty?
          raise ArgumentError, "servers is required" if servers.nil? || servers.empty?
          raise ArgumentError, "servers must be an array" unless servers.is_a?(Array)

          validate_server_refs(data, servers)

          app(data)["app"] ||= {}
          app(data)["app"][name.to_s] = {
            "servers" => servers.map(&:to_s),
            "domain" => domain,
            "subdomain" => subdomain,
            "port" => port,
            "command" => command,
            "pre_run_command" => pre_run_command,
            "env" => env,
            "mounts" => mounts
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

      class DeleteApp < Base
        protected

        def mutate(data, name:)
          raise ArgumentError, "name is required" if name.nil? || name.to_s.empty?

          apps = app(data)["app"] || {}
          raise Errors::ConfigValidationError, "app '#{name}' not found" unless apps.key?(name.to_s)

          apps.delete(name.to_s)
        end
      end
    end
  end
end
