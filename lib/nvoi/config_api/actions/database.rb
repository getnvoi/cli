# frozen_string_literal: true

module Nvoi
  module ConfigApi
    module Actions
      class SetDatabase < Base
        ADAPTERS = %w[postgres postgresql mysql sqlite sqlite3].freeze

        protected

          def mutate(data, servers:, adapter:, image: nil, url: nil, user: nil, password: nil, database: nil, mount: nil, path: nil)
            raise ArgumentError, "servers is required" if servers.nil? || servers.empty?
            raise ArgumentError, "servers must be an array" unless servers.is_a?(Array)
            raise ArgumentError, "adapter is required" if adapter.nil? || adapter.to_s.empty?
            raise ArgumentError, "adapter must be one of: #{ADAPTERS.join(', ')}" unless ADAPTERS.include?(adapter.to_s.downcase)

            validate_server_refs(data, servers)

            secrets = build_secrets(adapter, user, password, database)

            app(data)["database"] = {
              "servers" => servers.map(&:to_s),
              "adapter" => adapter.to_s,
              "image" => image,
              "url" => url,
              "secrets" => secrets.empty? ? nil : secrets,
              "mount" => mount,
              "path" => path
            }.compact
          end

        private

          def validate_server_refs(data, servers)
            defined = (app(data)["servers"] || {}).keys
            servers.each do |ref|
              raise Errors::ConfigValidationError, "server '#{ref}' not found" unless defined.include?(ref.to_s)
            end
          end

          def build_secrets(adapter, user, password, database)
            case adapter.to_s.downcase
            when "postgres", "postgresql"
              {
                "POSTGRES_USER" => user,
                "POSTGRES_PASSWORD" => password,
                "POSTGRES_DB" => database
              }.compact
            when "mysql"
              {
                "MYSQL_USER" => user,
                "MYSQL_PASSWORD" => password,
                "MYSQL_DATABASE" => database
              }.compact
            else
              {}
            end
          end
      end

      class DeleteDatabase < Base
        protected

          def mutate(data, **)
            app(data).delete("database")
          end
      end
    end
  end
end
