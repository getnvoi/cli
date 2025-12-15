# frozen_string_literal: true

require "test_helper"

class DeployCommandTest < Minitest::Test
  def test_command_initializes
    options = { config: "deploy.enc", dir: "." }
    command = Nvoi::Cli::Deploy::Command.new(options)

    assert_instance_of Nvoi::Cli::Deploy::Command, command
  end

  def test_resolve_config_path_default
    command = Nvoi::Cli::Deploy::Command.new({ config: nil, dir: nil })
    
    path = command.send(:resolve_config_path)
    
    assert_equal "deploy.enc", path
  end

  def test_resolve_config_path_with_dir
    command = Nvoi::Cli::Deploy::Command.new({ config: nil, dir: "/app" })
    
    path = command.send(:resolve_config_path)
    
    assert_equal "/app/deploy.enc", path
  end

  def test_resolve_config_path_explicit
    command = Nvoi::Cli::Deploy::Command.new({ config: "/custom/config.enc", dir: "/app" })
    
    path = command.send(:resolve_config_path)
    
    assert_equal "/custom/config.enc", path
  end

  def test_resolve_config_path_with_current_dir
    command = Nvoi::Cli::Deploy::Command.new({ config: "deploy.enc", dir: "." })
    
    path = command.send(:resolve_config_path)
    
    assert_equal "deploy.enc", path
  end
end
