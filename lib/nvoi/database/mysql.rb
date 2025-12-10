# frozen_string_literal: true

module Nvoi
  module Database
    # MySQL provider using mysqldump/mysql via kubectl exec
    class Mysql < Provider
      def default_port
        "3306"
      end

      # Parse mysql://user:pass@host:port/database
      def parse_url(url)
        parse_standard_url(url, default_port)
      end

      # Build mysql URL
      def build_url(creds, host: nil)
        h = host || creds.host
        "mysql://#{creds.user}:#{creds.password}@#{h}:#{creds.port}/#{creds.database}"
      end

      # Env vars for mysql container
      def container_env(creds)
        {
          "MYSQL_USER" => creds.user,
          "MYSQL_PASSWORD" => creds.password,
          "MYSQL_DATABASE" => creds.database,
          "MYSQL_ROOT_PASSWORD" => creds.password  # Required by mysql image
        }
      end

      # Env vars to inject into app services
      def app_env(creds, host:)
        {
          "DATABASE_URL" => build_url(creds, host:),
          "MYSQL_HOST" => host,
          "MYSQL_PORT" => creds.port,
          "MYSQL_USER" => creds.user,
          "MYSQL_PASSWORD" => creds.password,
          "MYSQL_DATABASE" => creds.database
        }
      end

      # Dump creates a MySQL dump using mysqldump
      def dump(ssh, opts)
        cmd = "kubectl exec -n default #{opts.pod_name} -- " \
              "mysqldump -u #{opts.user} -p#{opts.password} #{opts.database} " \
              "--single-transaction --routines --triggers"

        ssh.execute(cmd)
      rescue SSHCommandError => e
        raise DatabaseError.new("dump", "mysqldump failed: #{e.message}")
      end

      # Restore restores a MySQL database
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

        # Restore using mysql
        restore_cmd = "kubectl exec -n default #{opts.pod_name} -- " \
                      "sh -c 'mysql -u #{opts.user} -p#{opts.password} #{opts.database} < #{temp_file}'"
        ssh.execute(restore_cmd)

        # Cleanup temp files
        ssh.execute("rm -f #{temp_file}", raise_on_error: false)
        ssh.execute("kubectl exec -n default #{opts.pod_name} -- rm -f #{temp_file}", raise_on_error: false)
      rescue SSHCommandError => e
        raise DatabaseError.new("restore", "mysql restore failed: #{e.message}")
      end

      # Create a new MySQL database
      def create_database(ssh, opts)
        cmd = "kubectl exec -n default #{opts.pod_name} -- " \
              "mysql -u #{opts.user} -p#{opts.password} -e \"CREATE DATABASE #{opts.database}\""
        ssh.execute(cmd)
      rescue SSHCommandError => e
        raise DatabaseError.new("create_database", "failed to create database: #{e.message}")
      end
    end
  end
end
