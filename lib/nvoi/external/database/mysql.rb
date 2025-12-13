# frozen_string_literal: true

module Nvoi
  module External
    module Database
      # MySQL provider using mysqldump/mysql via kubectl exec
      class Mysql < Provider
        def default_port
          "3306"
        end

        def parse_url(url)
          parse_standard_url(url, default_port)
        end

        def build_url(creds, host: nil)
          h = host || creds.host
          "mysql://#{creds.user}:#{creds.password}@#{h}:#{creds.port}/#{creds.database}"
        end

        def container_env(creds)
          {
            "MYSQL_USER" => creds.user,
            "MYSQL_PASSWORD" => creds.password,
            "MYSQL_DATABASE" => creds.database,
            "MYSQL_ROOT_PASSWORD" => creds.password
          }
        end

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

        def dump(ssh, opts)
          cmd = "kubectl exec -n default #{opts.pod_name} -- " \
                "mysqldump -u #{opts.user} -p#{opts.password} #{opts.database} " \
                "--single-transaction --routines --triggers"
          ssh.execute(cmd)
        rescue Errors::SshCommandError => e
          raise Errors::DatabaseError.new("dump", "mysqldump failed: #{e.message}")
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
                        "sh -c 'mysql -u #{opts.user} -p#{opts.password} #{opts.database} < #{temp_file}'"
          ssh.execute(restore_cmd)

          ssh.execute_ignore_errors("rm -f #{temp_file}")
          ssh.execute_ignore_errors("kubectl exec -n default #{opts.pod_name} -- rm -f #{temp_file}")
        rescue Errors::SshCommandError => e
          raise Errors::DatabaseError.new("restore", "mysql restore failed: #{e.message}")
        end

        def create_database(ssh, opts)
          cmd = "kubectl exec -n default #{opts.pod_name} -- " \
                "mysql -u #{opts.user} -p#{opts.password} -e \"CREATE DATABASE #{opts.database}\""
          ssh.execute(cmd)
        rescue Errors::SshCommandError => e
          raise Errors::DatabaseError.new("create_database", "failed to create database: #{e.message}")
        end
      end
    end
  end
end
