# frozen_string_literal: true

module Nvoi
  module External
    # Database module provides database backup/restore operations
    module Database
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
end
