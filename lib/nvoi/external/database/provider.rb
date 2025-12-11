# frozen_string_literal: true

module Nvoi
  module External
    module Database
      # Base provider interface for database backup/restore operations
      class Provider
        def parse_url(url)
          raise NotImplementedError
        end

        def build_url(creds, host: nil)
          raise NotImplementedError
        end

        def container_env(creds)
          raise NotImplementedError
        end

        def app_env(creds, host:)
          raise NotImplementedError
        end

        def dump(ssh, opts)
          raise NotImplementedError
        end

        def restore(ssh, data, opts)
          raise NotImplementedError
        end

        def create_database(ssh, opts)
          raise NotImplementedError
        end

        def extension
          "sql"
        end

        def needs_container?
          true
        end

        def default_port
          raise NotImplementedError
        end

        protected

        def parse_standard_url(url, default_port)
          uri = URI.parse(url)
          Objects::DatabaseCredentials.new(
            user: uri.user,
            password: uri.password,
            host: uri.host,
            port: (uri.port || default_port).to_s,
            database: uri.path&.sub(%r{^/}, "")
          )
        rescue URI::InvalidURIError => e
          raise DatabaseError.new("parse_url", "invalid URL format: #{e.message}")
        end
      end

      # Factory method to create provider by adapter name
      def self.provider_for(adapter)
        case adapter&.downcase
        when "postgres", "postgresql"
          Postgres.new
        when "mysql", "mysql2"
          Mysql.new
        when "sqlite", "sqlite3"
          Sqlite.new
        else
          raise ArgumentError, "Unsupported database adapter: #{adapter}"
        end
      end
    end
  end
end
