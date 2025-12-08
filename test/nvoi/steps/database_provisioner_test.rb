# frozen_string_literal: true

require "test_helper"

class Nvoi::Steps::DatabaseProvisionerTest < Minitest::Test
  def setup
    @log = MockLogger.new
    @ssh = MockSSH.new
    @service_deployer = MockServiceDeployer.new
  end

  def test_skips_sqlite3_database
    config = mock_config(adapter: "sqlite3")

    Nvoi::Deployer::ServiceDeployer.stub(:new, @service_deployer) do
      provisioner = Nvoi::Steps::DatabaseProvisioner.new(config, @ssh, @log)
      provisioner.run
    end

    assert_includes @log.messages, "SQLite database will be provisioned with app deployment"
    refute @service_deployer.deploy_database_called
  end

  def test_provisions_postgres_database
    config = mock_config(adapter: "postgres", image: "postgres:15")

    # Mock returns Running immediately
    @ssh.add_response("kubectl get pods", "Running")

    # Stub BEFORE creating provisioner since ServiceDeployer is instantiated in initialize
    Nvoi::Deployer::ServiceDeployer.stub(:new, @service_deployer) do
      provisioner = Nvoi::Steps::DatabaseProvisioner.new(config, @ssh, @log)
      provisioner.run
    end

    assert @service_deployer.deploy_database_called
    assert_includes @log.messages, "Provisioning postgres database via K8s"
  end

  def test_returns_early_when_no_database_configured
    config = mock_config(adapter: nil)

    Nvoi::Deployer::ServiceDeployer.stub(:new, @service_deployer) do
      provisioner = Nvoi::Steps::DatabaseProvisioner.new(config, @ssh, @log)
      provisioner.run
    end

    refute @service_deployer.deploy_database_called
  end

  private

  def mock_config(adapter:, image: nil)
    db_config = if adapter
                  MockDatabaseConfig.new(adapter: adapter, image: image)
                end

    MockConfig.new(database: db_config)
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
  end

  class MockSSH
    def initialize
      @responses = {}
    end

    def add_response(pattern, response)
      @responses[pattern] = response
    end

    def execute(cmd, **_opts)
      @responses.each do |pattern, response|
        return response if cmd.include?(pattern)
      end
      "Running"
    end
  end

  class MockServiceDeployer
    attr_reader :deploy_database_called

    def initialize
      @deploy_database_called = false
    end

    def deploy_database(_spec)
      @deploy_database_called = true
    end
  end

  MockDatabaseConfig = Struct.new(:adapter, :image, :secrets, :servers, :volume, keyword_init: true) do
    def to_service_spec(namer)
      Struct.new(:name, :image, :port, :secrets, :servers).new(
        namer.database_service_name,
        image,
        5432,
        secrets || {},
        servers || []
      )
    end
  end

  class MockConfig
    attr_reader :deploy

    def initialize(database:)
      @deploy = MockDeploy.new(database: database)
    end

    def namer
      MockNamer.new
    end
  end

  class MockDeploy
    attr_reader :application

    def initialize(database:)
      @application = MockApplication.new(database: database)
    end
  end

  class MockApplication
    attr_reader :database

    def initialize(database:)
      @database = database
    end
  end

  class MockNamer
    def database_service_name
      "db-test"
    end

    def database_secret_name
      "db-test-secret"
    end

    def database_volume_name
      "db-test-volume"
    end
  end
end
