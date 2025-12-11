# frozen_string_literal: true

require "test_helper"

class CliTest < Minitest::Test
  def test_cli_class_exists
    assert_equal Nvoi::Cli.superclass, Thor
  end

  def test_exit_on_failure
    assert Nvoi::Cli.exit_on_failure?
  end

  def test_has_version_command
    assert Nvoi::Cli.all_commands.key?("version")
  end

  def test_has_deploy_command
    assert Nvoi::Cli.all_commands.key?("deploy")
  end

  def test_has_delete_command
    assert Nvoi::Cli.all_commands.key?("delete")
  end

  def test_has_exec_command
    assert Nvoi::Cli.all_commands.key?("exec")
  end

  def test_has_credentials_subcommand
    assert Nvoi::Cli.all_commands.key?("credentials")
  end

  def test_has_db_subcommand
    assert Nvoi::Cli.all_commands.key?("db")
  end

  def test_class_options
    options = Nvoi::Cli.class_options
    assert options.key?(:config)
    assert options.key?(:dir)
    assert options.key?(:branch)
  end
end
