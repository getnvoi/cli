# frozen_string_literal: true

module Nvoi
  module Database
    # SQLite provider using direct SSH file access on hostPath volume
    class Sqlite < Provider
      def default_port
        nil  # SQLite doesn't use ports
      end

      def needs_container?
        false  # SQLite doesn't need a separate container
      end

      # Parse sqlite://path/to/file.db
      def parse_url(url)
        # Handle: sqlite://path/to/file.db or sqlite:///absolute/path.db
        path = url.sub(%r{^sqlite3?:///?}, "")
        Credentials.new(
          path:,
          database: File.basename(path)
        )
      end

      # Build sqlite URL
      def build_url(creds, host: nil)
        "sqlite://#{creds.path}"
      end

      # Env vars for container - SQLite doesn't need any
      def container_env(_creds)
        {}
      end

      # Env vars to inject into app services
      def app_env(creds, host: nil)
        {
          "DATABASE_URL" => build_url(creds)
        }
      end

      # Dump creates a SQLite dump using sqlite3 .dump
      # Uses direct SSH access to hostPath volume (not kubectl exec)
      def dump(ssh, opts)
        db_path = opts.host_path
        raise DatabaseError.new("dump", "host_path required for SQLite dump") unless db_path

        # Run sqlite3 .dump directly on the server
        cmd = "sqlite3 #{db_path} .dump"
        ssh.execute(cmd)
      rescue SSHCommandError => e
        raise DatabaseError.new("dump", "sqlite3 dump failed: #{e.message}")
      end

      # Restore restores a SQLite database to a new file
      def restore(ssh, data, opts)
        db_path = opts.host_path
        raise DatabaseError.new("restore", "host_path required for SQLite restore") unless db_path

        # Generate new db path with branch id
        dir = File.dirname(db_path)
        new_db_path = "#{dir}/#{opts.database}.sqlite3"

        # Write dump to temp file
        temp_file = "/tmp/restore_#{opts.database}.sql"
        write_cmd = "cat > #{temp_file} << 'SQLDUMP'\n#{data}\nSQLDUMP"
        ssh.execute(write_cmd)

        # Create new database from dump
        restore_cmd = "sqlite3 #{new_db_path} < #{temp_file}"
        ssh.execute(restore_cmd)

        # Cleanup
        ssh.execute("rm -f #{temp_file}", raise_on_error: false)

        new_db_path
      rescue SSHCommandError => e
        raise DatabaseError.new("restore", "sqlite3 restore failed: #{e.message}")
      end

      # Create database is a no-op for SQLite (created on first write)
      def create_database(_ssh, _opts)
        # No-op for SQLite
      end
    end
  end
end
