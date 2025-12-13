# frozen_string_literal: true

require "json"

module Nvoi
  module External
    module Database
      # Parsed credentials from database URL
      Credentials = Struct.new(:user, :password, :host, :port, :database, :path, :host_path, keyword_init: true)

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
    end
  end
end
