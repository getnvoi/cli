# frozen_string_literal: true

require "test_helper"

class OnboardDatabaseStepTest < Minitest::Test
  def test_step_initializes
    prompt = Minitest::Mock.new
    step = Nvoi::Cli::Onboard::Steps::Database.new(prompt, test_mode: true)

    assert_instance_of Nvoi::Cli::Onboard::Steps::Database, step
  end

  def test_databases_constant
    databases = Nvoi::Cli::Onboard::Steps::Database::DATABASES
    adapters = databases.map { |d| d[:value]&.dig(:adapter) }.compact

    assert_includes adapters, "postgresql"
    assert_includes adapters, "mysql"
    assert_includes adapters, "sqlite3"
  end

  def test_postgres_pgvector_image
    databases = Nvoi::Cli::Onboard::Steps::Database::DATABASES
    pgvector = databases.find { |d| d[:name] == "PostgreSQL + pgvector" }

    assert_equal "postgresql", pgvector[:value][:adapter]
    assert_equal "pgvector/pgvector:pg17", pgvector[:value][:image]
  end
end
