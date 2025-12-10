# frozen_string_literal: true

module Nvoi
  module Database
    # PostgreSQL provider using pg_dump/psql via kubectl exec
    class Postgres < Provider
      def default_port
        "5432"
      end

      # Parse postgres://user:pass@host:port/database
      def parse_url(url)
        parse_standard_url(url, default_port)
      end

      # Build postgres URL
      def build_url(creds, host: nil)
        h = host || creds.host
        "postgresql://#{creds.user}:#{creds.password}@#{h}:#{creds.port}/#{creds.database}"
      end

      # Env vars for postgres container
      def container_env(creds)
        {
          "POSTGRES_USER" => creds.user,
          "POSTGRES_PASSWORD" => creds.password,
          "POSTGRES_DB" => creds.database
        }
      end

      # Env vars to inject into app services
      def app_env(creds, host:)
        {
          "DATABASE_URL" => build_url(creds, host:),
          "POSTGRES_HOST" => host,
          "POSTGRES_PORT" => creds.port,
          "POSTGRES_USER" => creds.user,
          "POSTGRES_PASSWORD" => creds.password,
          "POSTGRES_DB" => creds.database
        }
      end

      # Dump creates a PostgreSQL dump using pg_dump
      def dump(ssh, opts)
        cmd = "kubectl exec -n default #{opts.pod_name} -- " \
              "pg_dump -U #{opts.user} -d #{opts.database} --no-owner --no-acl"

        ssh.execute(cmd)
      rescue SSHCommandError => e
        raise DatabaseError.new("dump", "pg_dump failed: #{e.message}")
      end

      # Restore restores a PostgreSQL database using psql
      def restore(ssh, data, opts)
        # First create the new database
        create_database(ssh, CreateOptions.new(
          pod_name: opts.pod_name,
          database: opts.database,
          user: opts.user,
          password: opts.password
        ))

        # Write dump to temp file on remote
        temp_file = "/tmp/restore_#{opts.database}.sql"
        write_cmd = "cat > #{temp_file} << 'SQLDUMP'\n#{data}\nSQLDUMP"
        ssh.execute(write_cmd)

        # Copy into pod
        copy_cmd = "kubectl cp #{temp_file} default/#{opts.pod_name}:#{temp_file}"
        ssh.execute(copy_cmd)

        # Restore using psql
        restore_cmd = "kubectl exec -n default #{opts.pod_name} -- " \
                      "psql -U #{opts.user} -d #{opts.database} -f #{temp_file}"
        ssh.execute(restore_cmd)

        # Cleanup temp files
        ssh.execute("rm -f #{temp_file}", raise_on_error: false)
        ssh.execute("kubectl exec -n default #{opts.pod_name} -- rm -f #{temp_file}", raise_on_error: false)
      rescue SSHCommandError => e
        raise DatabaseError.new("restore", "psql restore failed: #{e.message}")
      end

      # Create a new PostgreSQL database
      def create_database(ssh, opts)
        cmd = "kubectl exec -n default #{opts.pod_name} -- " \
              "psql -U #{opts.user} -c \"CREATE DATABASE #{opts.database}\""
        ssh.execute(cmd)
      rescue SSHCommandError => e
        raise DatabaseError.new("create_database", "failed to create database: #{e.message}")
      end
    end
  end
end
