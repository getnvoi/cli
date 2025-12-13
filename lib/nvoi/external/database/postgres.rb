# frozen_string_literal: true

module Nvoi
  module External
    module Database
      # PostgreSQL provider using pg_dump/psql via kubectl exec
      class Postgres < Provider
        def default_port
          "5432"
        end

        def parse_url(url)
          parse_standard_url(url, default_port)
        end

        def build_url(creds, host: nil)
          h = host || creds.host
          "postgresql://#{creds.user}:#{creds.password}@#{h}:#{creds.port}/#{creds.database}"
        end

        def container_env(creds)
          {
            "POSTGRES_USER" => creds.user,
            "POSTGRES_PASSWORD" => creds.password,
            "POSTGRES_DB" => creds.database
          }
        end

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

        def dump(ssh, opts)
          cmd = "kubectl exec -n default #{opts.pod_name} -- " \
                "pg_dump -U #{opts.user} -d #{opts.database} --no-owner --no-acl"
          ssh.execute(cmd)
        rescue Errors::SshCommandError => e
          raise Errors::DatabaseError.new("dump", "pg_dump failed: #{e.message}")
        end

        def restore(ssh, data, opts)
          create_database(ssh, Database::CreateOptions.new(
            pod_name: opts.pod_name,
            database: opts.database,
            user: opts.user,
            password: opts.password
          ))

          temp_file = "/tmp/restore_#{opts.database}.sql"
          write_cmd = "cat > #{temp_file} << 'SQLDUMP'\n#{data}\nSQLDUMP"
          ssh.execute(write_cmd)

          ssh.execute("kubectl cp #{temp_file} default/#{opts.pod_name}:#{temp_file}")

          restore_cmd = "kubectl exec -n default #{opts.pod_name} -- " \
                        "psql -U #{opts.user} -d #{opts.database} -f #{temp_file}"
          ssh.execute(restore_cmd)

          ssh.execute_ignore_errors("rm -f #{temp_file}")
          ssh.execute_ignore_errors("kubectl exec -n default #{opts.pod_name} -- rm -f #{temp_file}")
        rescue Errors::SshCommandError => e
          raise Errors::DatabaseError.new("restore", "psql restore failed: #{e.message}")
        end

        def create_database(ssh, opts)
          cmd = "kubectl exec -n default #{opts.pod_name} -- " \
                "psql -U #{opts.user} -c \"CREATE DATABASE #{opts.database}\""
          ssh.execute(cmd)
        rescue Errors::SshCommandError => e
          raise Errors::DatabaseError.new("create_database", "failed to create database: #{e.message}")
        end
      end
    end
  end
end
