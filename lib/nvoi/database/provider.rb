# frozen_string_literal: true

module Nvoi
  module Database
    # Parsed credentials from URL
    Credentials = Struct.new(:user, :password, :host, :port, :database, :path, keyword_init: true)

    # Base provider interface for database backup/restore operations
    class Provider
      # Parse a database URL and return credentials
      # @param url [String] Database URL (e.g., postgres://user:pass@host:5432/db)
      # @return [Credentials]
      def parse_url(url)
        raise NotImplementedError, "#{self.class}#parse_url not implemented"
      end

      # Build a database URL from credentials
      # @param creds [Credentials]
      # @param host [String] Override host (for k8s service name)
      # @return [String]
      def build_url(creds, host: nil)
        raise NotImplementedError, "#{self.class}#build_url not implemented"
      end

      # Return env vars needed for the database container
      # @param creds [Credentials]
      # @return [Hash<String, String>]
      def container_env(creds)
        raise NotImplementedError, "#{self.class}#container_env not implemented"
      end

      # Return env vars to inject into app services
      # @param creds [Credentials]
      # @param host [String] Database host (k8s service name)
      # @return [Hash<String, String>]
      def app_env(creds, host:)
        raise NotImplementedError, "#{self.class}#app_env not implemented"
      end

      # Dump creates a database dump and returns the raw bytes
      # @param ssh [SSHExecutor] SSH connection to server
      # @param opts [DumpOptions] Options for the dump
      # @return [String] Raw dump content
      def dump(ssh, opts)
        raise NotImplementedError, "#{self.class}#dump not implemented"
      end

      # Restore restores a database from dump content into a new database
      # @param ssh [SSHExecutor] SSH connection to server
      # @param data [String] Dump content to restore
      # @param opts [RestoreOptions] Options for the restore
      def restore(ssh, data, opts)
        raise NotImplementedError, "#{self.class}#restore not implemented"
      end

      # Create a new empty database
      # @param ssh [SSHExecutor] SSH connection to server
      # @param opts [CreateOptions] Options for creating the database
      def create_database(ssh, opts)
        raise NotImplementedError, "#{self.class}#create_database not implemented"
      end

      # Returns the file extension for dumps (e.g., "sql")
      # @return [String]
      def extension
        "sql"
      end

      # Does this adapter need a container? (false for sqlite)
      # @return [Boolean]
      def needs_container?
        true
      end

      # Default port for this database
      # @return [String]
      def default_port
        raise NotImplementedError, "#{self.class}#default_port not implemented"
      end

      protected

        # Parse standard database URL format
        # @param url [String]
        # @param default_port [String]
        # @return [Credentials]
        def parse_standard_url(url, default_port)
          # Handle: adapter://user:pass@host:port/database
          uri = URI.parse(url)
          Credentials.new(
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

    # Options for dumping a database
    DumpOptions = Struct.new(:pod_name, :database, :user, :password, :host_path, keyword_init: true)

    # Options for restoring a database
    RestoreOptions = Struct.new(:pod_name, :database, :user, :password, :source_db, :host_path, keyword_init: true)

    # Options for creating a database
    CreateOptions = Struct.new(:pod_name, :database, :user, :password, keyword_init: true)

    # Branch represents a database branch (snapshot)
    Branch = Struct.new(:id, :created_at, :size, :adapter, :database, keyword_init: true) do
      def to_h
        { id:, created_at:, size:, adapter:, database: }
      end
    end

    # BranchMetadata holds all branches for an app
    class BranchMetadata
      attr_accessor :branches

      def initialize(branches = [])
        @branches = branches
      end

      def to_json(*_args)
        JSON.pretty_generate({ branches: @branches.map(&:to_h) })
      end

      def self.from_json(json_str)
        data = JSON.parse(json_str)
        branches = (data["branches"] || []).map do |b|
          Branch.new(
            id: b["id"],
            created_at: b["created_at"],
            size: b["size"],
            adapter: b["adapter"],
            database: b["database"]
          )
        end
        new(branches)
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
