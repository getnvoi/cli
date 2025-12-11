# frozen_string_literal: true

module Nvoi
  module External
    module Database
      # SQLite provider using direct SSH file access on hostPath volume
      class Sqlite < Provider
        def default_port
          nil
        end

        def needs_container?
          false
        end

        def parse_url(url)
          path = url.sub(%r{^sqlite3?:///?}, "")
          Objects::Database::Credentials.new(
            path:,
            database: File.basename(path)
          )
        end

        def build_url(creds, host: nil)
          "sqlite://#{creds.path}"
        end

        def container_env(_creds)
          {}
        end

        def app_env(creds, host: nil)
          {
            "DATABASE_URL" => build_url(creds)
          }
        end

        def dump(ssh, opts)
          db_path = opts.host_path
          raise Errors::DatabaseError.new("dump", "host_path required for SQLite dump") unless db_path

          ssh.execute("sqlite3 #{db_path} .dump")
        rescue Errors::SshCommandError => e
          raise Errors::DatabaseError.new("dump", "sqlite3 dump failed: #{e.message}")
        end

        def restore(ssh, data, opts)
          db_path = opts.host_path
          raise Errors::DatabaseError.new("restore", "host_path required for SQLite restore") unless db_path

          dir = File.dirname(db_path)
          new_db_path = "#{dir}/#{opts.database}.sqlite3"

          temp_file = "/tmp/restore_#{opts.database}.sql"
          write_cmd = "cat > #{temp_file} << 'SQLDUMP'\n#{data}\nSQLDUMP"
          ssh.execute(write_cmd)

          ssh.execute("sqlite3 #{new_db_path} < #{temp_file}")
          ssh.execute_ignore_errors("rm -f #{temp_file}")

          new_db_path
        rescue Errors::SshCommandError => e
          raise Errors::DatabaseError.new("restore", "sqlite3 restore failed: #{e.message}")
        end

        def create_database(_ssh, _opts)
          # No-op for SQLite
        end
      end
    end
  end
end
