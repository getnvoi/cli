# frozen_string_literal: true

module Nvoi
  class Cli
    module Onboard
      module Steps
        # Collects database configuration
        class Database
          include UI

          ADAPTERS = [
            { name: "PostgreSQL", value: "postgres" },
            { name: "MySQL", value: "mysql" },
            { name: "SQLite", value: "sqlite3" },
            { name: "None (skip)", value: nil }
          ].freeze

          def initialize(prompt, test_mode: false)
            @prompt = prompt
            @test_mode = test_mode
          end

          # Returns [db_config, volume_config] tuple
          def call(app_name:, existing: nil)
            section "Database"

            adapter = @prompt.select("Database:", ADAPTERS)
            return [nil, nil] unless adapter

            case adapter
            when "postgres" then setup_postgres(app_name)
            when "mysql"    then setup_mysql(app_name)
            when "sqlite3"  then setup_sqlite
            end
          end

          private

          def setup_postgres(app_name)
            db_name = @prompt.ask("Database name:", default: "#{app_name}_production")
            user = @prompt.ask("Database user:", default: app_name)
            password = @prompt.mask("Database password:") { |q| q.required true }

            config = {
              "servers" => ["main"],
              "adapter" => "postgres",
              "secrets" => {
                "POSTGRES_DB" => db_name,
                "POSTGRES_USER" => user,
                "POSTGRES_PASSWORD" => password
              }
            }

            volume = { "postgres_data" => { "size" => 10 } }

            [config, volume]
          end

          def setup_mysql(app_name)
            db_name = @prompt.ask("Database name:", default: "#{app_name}_production")
            user = @prompt.ask("Database user:", default: app_name)
            password = @prompt.mask("Database password:") { |q| q.required true }

            config = {
              "servers" => ["main"],
              "adapter" => "mysql",
              "secrets" => {
                "MYSQL_DATABASE" => db_name,
                "MYSQL_USER" => user,
                "MYSQL_PASSWORD" => password
              }
            }

            volume = { "mysql_data" => { "size" => 10 } }

            [config, volume]
          end

          def setup_sqlite
            path = @prompt.ask("Database path:", default: "/app/data/production.sqlite3")

            config = {
              "servers" => ["main"],
              "adapter" => "sqlite3",
              "path" => path,
              "mount" => { "data" => "/app/data" }
            }

            volume = { "sqlite_data" => { "size" => 10 } }

            [config, volume]
          end
        end
      end
    end
  end
end
