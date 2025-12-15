# frozen_string_literal: true

module Nvoi
  class Cli
    module Onboard
      module Steps
        # Collects database configuration
        class Database
          include Onboard::Ui

          DATABASES = [
            { name: "PostgreSQL", value: { adapter: "postgresql", image: "postgres:17-alpine" } },
            { name: "PostgreSQL + pgvector", value: { adapter: "postgresql", image: "pgvector/pgvector:pg17" } },
            { name: "MySQL", value: { adapter: "mysql", image: "mysql:8" } },
            { name: "SQLite", value: { adapter: "sqlite3", image: nil } },
            { name: "None (skip)", value: nil }
          ].freeze

          def initialize(prompt, test_mode: false)
            @prompt = prompt
            @test_mode = test_mode
          end

          # Returns [db_config, volume_config] tuple
          def call(app_name:, existing: nil)
            section "Database"

            selection = @prompt.select("Database:", DATABASES)
            return [nil, nil] unless selection

            case selection[:adapter]
            when "postgresql" then setup_postgres(app_name, selection[:image])
            when "mysql"      then setup_mysql(app_name, selection[:image])
            when "sqlite3"    then setup_sqlite
            end
          end

          private

            def setup_postgres(app_name, image)
              db_name = @prompt.ask("Database name:", default: "#{app_name}_production")
              user = @prompt.ask("Database user:", default: app_name)
              password = @prompt.mask("Database password:") { |q| q.required true }

              config = {
                "servers" => ["main"],
                "adapter" => "postgresql",
                "image" => image,
                "secrets" => {
                  "POSTGRES_DB" => db_name,
                  "POSTGRES_USER" => user,
                  "POSTGRES_PASSWORD" => password
                }
              }

              volume = { "db" => { "size" => 10 } }

              [config, volume]
            end

            def setup_mysql(app_name, image)
              db_name = @prompt.ask("Database name:", default: "#{app_name}_production")
              user = @prompt.ask("Database user:", default: app_name)
              password = @prompt.mask("Database password:") { |q| q.required true }

              config = {
                "servers" => ["main"],
                "adapter" => "mysql",
                "image" => image,
                "secrets" => {
                  "MYSQL_DATABASE" => db_name,
                  "MYSQL_USER" => user,
                  "MYSQL_PASSWORD" => password
                }
              }

              volume = { "db" => { "size" => 10 } }

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
