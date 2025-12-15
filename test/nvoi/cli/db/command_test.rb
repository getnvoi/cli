# frozen_string_literal: true

require "test_helper"

class DbCommandTest < Minitest::Test
  def test_command_initializes
    options = { config: "deploy.enc", dir: "." }
    command = Nvoi::Cli::Db::Command.new(options)

    assert_instance_of Nvoi::Cli::Db::Command, command
  end

  def test_branches_dir_constant
    assert_equal "/mnt/db-branches", Nvoi::Cli::Db::Command::BRANCHES_DIR
  end

  def test_generate_branch_id_format
    command = Nvoi::Cli::Db::Command.new({})
    
    # Access private method for testing
    branch_id = command.send(:generate_branch_id)
    
    assert_match(/\A\d{8}-\d{6}\z/, branch_id)
  end

  def test_sanitize_db_name_removes_special_chars
    command = Nvoi::Cli::Db::Command.new({})
    
    result = command.send(:sanitize_db_name, "my-db.name!@#")
    
    assert_equal "my_db_name___", result
  end

  def test_format_size_bytes
    command = Nvoi::Cli::Db::Command.new({})
    
    assert_equal "0 B", command.send(:format_size, nil)
    assert_equal "100.0 B", command.send(:format_size, 100)
    assert_equal "1.0 KB", command.send(:format_size, 1024)
    assert_equal "1.0 MB", command.send(:format_size, 1024 * 1024)
    assert_equal "1.0 GB", command.send(:format_size, 1024 * 1024 * 1024)
  end

  def test_resolve_config_path_default
    command = Nvoi::Cli::Db::Command.new({ config: nil, dir: nil })
    
    path = command.send(:resolve_config_path)
    
    assert_equal "deploy.enc", path
  end

  def test_resolve_config_path_with_dir
    command = Nvoi::Cli::Db::Command.new({ config: nil, dir: "/app" })
    
    path = command.send(:resolve_config_path)
    
    assert_equal "/app/deploy.enc", path
  end

  def test_resolve_config_path_explicit
    command = Nvoi::Cli::Db::Command.new({ config: "/custom/config.enc", dir: "/app" })
    
    path = command.send(:resolve_config_path)
    
    assert_equal "/custom/config.enc", path
  end
end
