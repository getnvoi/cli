# frozen_string_literal: true

require "test_helper"

class OnboardDatabaseStepTest < Minitest::Test
  def test_step_initializes
    prompt = Minitest::Mock.new
    step = Nvoi::Cli::Onboard::Steps::Database.new(prompt, test_mode: true)

    assert_instance_of Nvoi::Cli::Onboard::Steps::Database, step
  end

  def test_adapters_constant
    adapters = Nvoi::Cli::Onboard::Steps::Database::ADAPTERS

    assert_includes adapters.map { |a| a[:value] }, "postgres"
    assert_includes adapters.map { |a| a[:value] }, "mysql"
    assert_includes adapters.map { |a| a[:value] }, "sqlite3"
  end
end
