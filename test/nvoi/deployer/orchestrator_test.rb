# frozen_string_literal: true

require "test_helper"

class Nvoi::Deployer::OrchestratorTest < Minitest::Test
  def setup
    @log = MockLogger.new
    @ssh = MockSSH.new
    @deploy_database_called = false
    @deployed_db_spec = nil
    @deployed_secret_env = nil
  end

  def test_skips_database_deployment_for_sqlite3
    config = build_config(adapter: "sqlite3")

    run_orchestrator_deployment(config)

    refute @deploy_database_called, "deploy_database should not be called for sqlite3"
  end

  def test_deploys_database_for_postgres
    config = build_config(adapter: "postgres")

    run_orchestrator_deployment(config)

    assert @deploy_database_called, "deploy_database should be called for postgres"
    assert_equal "db-myapp", @deployed_db_spec.name
  end

  def test_skips_database_deployment_when_no_database_configured
    config = build_config(adapter: nil)

    run_orchestrator_deployment(config)

    refute @deploy_database_called, "deploy_database should not be called when no database configured"
  end

  def test_deploy_app_secret_receives_database_env_vars_for_sqlite
    config = build_config(adapter: "sqlite3", env: { "APP_NAME" => "myapp" })

    run_orchestrator_deployment(config)

    assert @deployed_secret_env, "deploy_app_secret should have been called"
    assert_equal "sqlite3", @deployed_secret_env["DATABASE_ADAPTER"]
    assert_equal "sqlite://data/db/production.sqlite3", @deployed_secret_env["DATABASE_URL"]
    assert_equal "production", @deployed_secret_env["DEPLOY_ENV"]
    assert_equal "myapp", @deployed_secret_env["APP_NAME"]
  end

  def test_deploy_app_secret_receives_database_env_vars_for_postgres
    config = build_config(adapter: "postgres", env: { "APP_NAME" => "myapp" })

    run_orchestrator_deployment(config)

    assert @deployed_secret_env, "deploy_app_secret should have been called"
    assert_equal "postgres", @deployed_secret_env["DATABASE_ADAPTER"]
    assert_equal "production", @deployed_secret_env["DEPLOY_ENV"]
  end

  def test_deploy_app_secret_receives_database_env_vars_for_mysql
    config = build_config(adapter: "mysql2", env: { "APP_NAME" => "myapp" })

    run_orchestrator_deployment(config)

    assert @deployed_secret_env, "deploy_app_secret should have been called"
    assert_equal "mysql2", @deployed_secret_env["DATABASE_ADAPTER"]
    assert_equal "production", @deployed_secret_env["DEPLOY_ENV"]
  end

  private

    def run_orchestrator_deployment(config)
      # Stub ServiceDeployer to capture deploy_database calls
      service_deployer = mock_service_deployer

      Nvoi::Deployer::ServiceDeployer.stub(:new, service_deployer) do
        Nvoi::Deployer::ImageBuilder.stub(:new, mock_image_builder) do
          Nvoi::Deployer::Cleaner.stub(:new, mock_cleaner) do
            Nvoi::Remote::SSHExecutor.stub(:new, @ssh) do
              Nvoi::Remote::DockerManager.stub(:new, mock_docker) do
                orchestrator = Nvoi::Deployer::Orchestrator.new(config, mock_provider, @log)
                orchestrator.run("1.2.3.4", [], "/tmp/test")
              end
            end
          end
        end
      end
    end

    def build_config(adapter:, env: {})
      OrchestratorTestConfig.new(adapter:, env:)
    end

    def mock_service_deployer
      test_instance = self
      Object.new.tap do |deployer|
        deployer.define_singleton_method(:deploy_app_secret) do |env|
          test_instance.instance_variable_set(:@deployed_secret_env, env)
        end
        deployer.define_singleton_method(:deploy_database) do |spec|
          test_instance.instance_variable_set(:@deploy_database_called, true)
          test_instance.instance_variable_set(:@deployed_db_spec, spec)
        end
        deployer.define_singleton_method(:deploy_service) { |_, _| }
        deployer.define_singleton_method(:deploy_app_service) { |_, _, _, _| }
        deployer.define_singleton_method(:deploy_cloudflared) { |_, _| }
        deployer.define_singleton_method(:verify_traffic_switchover) { |_| }
      end
    end

    def mock_image_builder
      Object.new.tap do |builder|
        builder.define_singleton_method(:build_and_push) { |_, _| }
      end
    end

    def mock_cleaner
      Object.new.tap do |cleaner|
        cleaner.define_singleton_method(:cleanup_old_images) { |_| }
      end
    end

    def mock_docker
      Object.new
    end

    def mock_provider
      Object.new
    end

    class MockLogger
      attr_reader :messages

      def initialize
        @messages = []
      end

      def info(msg, *args)
        @messages << (args.empty? ? msg : format(msg, *args))
      end

      def success(msg, *args)
        @messages << (args.empty? ? msg : format(msg, *args))
      end

      def warning(msg, *args)
        @messages << (args.empty? ? msg : format(msg, *args))
      end
    end

    class MockSSH
      def execute(_cmd, **_opts)
        ""
      end
    end

    class OrchestratorTestConfig
      attr_reader :ssh_key_path, :container_prefix

      def initialize(adapter:, env: {})
        @adapter = adapter
        @env = env
        @ssh_key_path = "/tmp/test_key"
        @container_prefix = "test-app"
      end

      def deploy
        @deploy ||= OrchestratorTestDeploy.new(@adapter, @env)
      end

      def namer
        @namer ||= OrchestratorTestNamer.new
      end

      def env_for_service(_name)
        env = { "DEPLOY_ENV" => "production" }
        env.merge!(@env)
        if @adapter
          env["DATABASE_ADAPTER"] = @adapter
          env["DATABASE_URL"] = "sqlite://data/db/production.sqlite3" if @adapter == "sqlite3"
        end
        env
      end
    end

    class OrchestratorTestDeploy
      def initialize(adapter, env = {})
        @adapter = adapter
        @env = env
      end

      def application
        @application ||= OrchestratorTestApplication.new(@adapter, @env)
      end
    end

    class OrchestratorTestApplication
      attr_reader :env, :secrets, :services, :app, :environment

      def initialize(adapter, env = {})
        @adapter = adapter
        @env = env
        @secrets = {}
        @services = {}
        @app = {}
        @environment = "production"
      end

      def database
        return nil unless @adapter

        OrchestratorTestDatabase.new(@adapter)
      end
    end

    class OrchestratorTestDatabase
      attr_reader :adapter

      def initialize(adapter)
        @adapter = adapter
      end

      def to_service_spec(namer)
        # Returns nil for sqlite3, matching real behavior
        return nil if @adapter == "sqlite3"

        Struct.new(:name, :image, :port, :secrets, :servers).new(
          namer.database_service_name,
          "postgres:15",
          5432,
          {},
          []
        )
      end
    end

    class OrchestratorTestNamer
      def image_tag(timestamp)
        "test-app:#{timestamp}"
      end

      def deployment_lock_file_path
        "/tmp/nvoi/deploy.lock"
      end

      def database_service_name
        "db-myapp"
      end

      def database_secret_name
        "db-myapp-secret"
      end

      def server_volume_name(server_name, volume_name)
        "myapp-#{server_name}-#{volume_name}"
      end

      def server_volume_host_path(server_name, volume_name)
        "/opt/nvoi/volumes/#{server_volume_name(server_name, volume_name)}"
      end
    end
end
