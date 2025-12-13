# frozen_string_literal: true

require "test_helper"

class DatabaseTypesTest < Minitest::Test
  def test_database_credentials_struct
    creds = Nvoi::External::Database::Credentials.new(
      user: "postgres",
      password: "secret",
      host: "localhost",
      port: "5432",
      database: "myapp_prod",
      path: nil
    )

    assert_equal "postgres", creds.user
    assert_equal "secret", creds.password
    assert_equal "localhost", creds.host
    assert_equal "5432", creds.port
    assert_equal "myapp_prod", creds.database
    assert_nil creds.path
  end

  def test_dump_options_struct
    opts = Nvoi::External::Database::DumpOptions.new(
      pod_name: "myapp-db-0",
      database: "myapp_prod",
      user: "postgres",
      password: "secret",
      host_path: "/mnt/data/branches"
    )

    assert_equal "myapp-db-0", opts.pod_name
    assert_equal "myapp_prod", opts.database
    assert_equal "postgres", opts.user
    assert_equal "secret", opts.password
    assert_equal "/mnt/data/branches", opts.host_path
  end

  def test_restore_options_struct
    opts = Nvoi::External::Database::RestoreOptions.new(
      pod_name: "myapp-db-0",
      database: "myapp_branch",
      user: "postgres",
      password: "secret",
      source_db: "myapp_prod",
      host_path: "/mnt/data/branches"
    )

    assert_equal "myapp-db-0", opts.pod_name
    assert_equal "myapp_branch", opts.database
    assert_equal "postgres", opts.user
    assert_equal "secret", opts.password
    assert_equal "myapp_prod", opts.source_db
    assert_equal "/mnt/data/branches", opts.host_path
  end

  def test_database_create_options_struct
    opts = Nvoi::External::Database::CreateOptions.new(
      pod_name: "myapp-db-0",
      database: "myapp_branch",
      user: "postgres",
      password: "secret"
    )

    assert_equal "myapp-db-0", opts.pod_name
    assert_equal "myapp_branch", opts.database
    assert_equal "postgres", opts.user
    assert_equal "secret", opts.password
  end

  def test_branch_struct
    branch = Nvoi::External::Database::Branch.new(
      id: "branch-123",
      created_at: "2024-01-15T10:30:00Z",
      size: 1024,
      adapter: "postgres",
      database: "myapp_prod"
    )

    assert_equal "branch-123", branch.id
    assert_equal "2024-01-15T10:30:00Z", branch.created_at
    assert_equal 1024, branch.size
    assert_equal "postgres", branch.adapter
    assert_equal "myapp_prod", branch.database
  end

  def test_branch_to_h
    branch = Nvoi::External::Database::Branch.new(
      id: "branch-123",
      created_at: "2024-01-15T10:30:00Z",
      size: 1024,
      adapter: "postgres",
      database: "myapp_prod"
    )

    hash = branch.to_h
    assert_equal "branch-123", hash[:id]
    assert_equal "2024-01-15T10:30:00Z", hash[:created_at]
    assert_equal 1024, hash[:size]
    assert_equal "postgres", hash[:adapter]
    assert_equal "myapp_prod", hash[:database]
  end

  def test_branch_metadata_to_json
    branches = [
      Nvoi::External::Database::Branch.new(id: "b1", created_at: "2024-01-15", size: 100, adapter: "postgres", database: "db1"),
      Nvoi::External::Database::Branch.new(id: "b2", created_at: "2024-01-16", size: 200, adapter: "postgres", database: "db2")
    ]
    metadata = Nvoi::External::Database::BranchMetadata.new(branches)

    json = metadata.to_json
    parsed = JSON.parse(json)

    assert_equal 2, parsed["branches"].size
    assert_equal "b1", parsed["branches"][0]["id"]
    assert_equal "b2", parsed["branches"][1]["id"]
  end

  def test_branch_metadata_from_json
    json = '{"branches":[{"id":"b1","created_at":"2024-01-15","size":100,"adapter":"postgres","database":"db1"}]}'
    metadata = Nvoi::External::Database::BranchMetadata.from_json(json)

    assert_equal 1, metadata.branches.size
    assert_equal "b1", metadata.branches[0].id
    assert_equal "postgres", metadata.branches[0].adapter
  end

  def test_branch_metadata_empty
    metadata = Nvoi::External::Database::BranchMetadata.new
    assert_equal [], metadata.branches

    json = metadata.to_json
    parsed = JSON.parse(json)
    assert_equal [], parsed["branches"]
  end
end
