# frozen_string_literal: true

module Nvoi
  module Config
    # DatabaseCredentials holds extracted database connection info
    # This is a compatibility wrapper around Database::Credentials
    class DatabaseCredentials
      attr_reader :adapter, :user, :password, :database, :port, :host_path, :path

      def initialize(adapter:, user: nil, password: nil, database: nil, port: nil, host_path: nil, path: nil)
        @adapter = adapter
        @user = user
        @password = password
        @database = database
        @port = port
        @host_path = host_path
        @path = path
      end

      def sqlite?
        %w[sqlite sqlite3].include?(adapter&.downcase)
      end
    end

    # Helper methods for database configuration
    module DatabaseHelper
      module_function

      # Extract credentials from DatabaseConfig based on adapter
      # Uses database providers for parsing URL when available
      # @param db_config [DatabaseConfig] Database configuration
      # @param namer [Naming] Resource namer for resolving paths
      # @return [DatabaseCredentials]
      def get_credentials(db_config, namer = nil)
        return nil unless db_config

        adapter = db_config.adapter&.downcase
        return nil unless adapter

        # Get the provider for this adapter
        provider = Database.provider_for(adapter)

        # URL takes precedence
        if db_config.url && !db_config.url.empty?
          creds = provider.parse_url(db_config.url)

          # For SQLite, resolve host_path
          host_path = nil
          if provider.is_a?(Database::Sqlite)
            host_path = resolve_sqlite_host_path(db_config, namer, creds.database || "app.db")
          end

          return DatabaseCredentials.new(
            adapter:,
            user: creds.user,
            password: creds.password,
            database: creds.database,
            port: creds.port,
            path: creds.path,
            host_path:
          )
        end

        # Fall back to secrets-based credentials
        case adapter
        when "postgres", "postgresql"
          DatabaseCredentials.new(
            adapter:,
            port: provider.default_port,
            user: db_config.secrets["POSTGRES_USER"],
            password: db_config.secrets["POSTGRES_PASSWORD"],
            database: db_config.secrets["POSTGRES_DB"]
          )
        when "mysql", "mysql2"
          DatabaseCredentials.new(
            adapter:,
            port: provider.default_port,
            user: db_config.secrets["MYSQL_USER"],
            password: db_config.secrets["MYSQL_PASSWORD"],
            database: db_config.secrets["MYSQL_DATABASE"]
          )
        when "sqlite", "sqlite3"
          # SQLite should always use URL, but handle edge case
          DatabaseCredentials.new(
            adapter:,
            database: "app.db",
            host_path: resolve_sqlite_host_path(db_config, namer, "app.db")
          )
        else
          raise ConfigError, "Unsupported database adapter: #{adapter}"
        end
      end

      # Build a DATABASE_URL from credentials using provider
      # @param creds [DatabaseCredentials]
      # @param host [String] Database host (for postgres/mysql)
      # @return [String]
      def build_database_url(creds, host = nil)
        provider = Database.provider_for(creds.adapter)

        # Convert to Database::Credentials for provider
        db_creds = Database::Credentials.new(
          user: creds.user,
          password: creds.password,
          host:,
          port: creds.port,
          database: creds.database,
          path: creds.path || creds.database
        )

        provider.build_url(db_creds, host:)
      end

      # Resolve the host path for SQLite database from mount configuration
      # @param db_config [DatabaseConfig]
      # @param namer [Naming]
      # @param filename [String] SQLite filename
      # @return [String, nil]
      def resolve_sqlite_host_path(db_config, namer, filename = "app.db")
        return nil unless namer && db_config.servers&.any?

        server_name = db_config.servers.first
        mount = db_config.mount

        # If database has a mount, use it
        if mount && !mount.empty?
          vol_name = mount.keys.first
          base_path = namer.server_volume_host_path(server_name, vol_name)
          return "#{base_path}/#{filename}"
        end

        nil
      end

      # Sanitize database name (only alphanumeric and underscore)
      # @param name [String]
      # @return [String]
      def sanitize_db_name(name)
        name.gsub(/[^a-zA-Z0-9_]/, "_")
      end
    end
  end
end
