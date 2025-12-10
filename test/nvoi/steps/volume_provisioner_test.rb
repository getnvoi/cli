# frozen_string_literal: true

require "test_helper"

class Nvoi::Steps::VolumeProvisionerTest < Minitest::Test
  def test_collect_volumes_from_server_config
    config = build_config_with_volumes
    provisioner = Nvoi::Steps::VolumeProvisioner.new(config, MockProvider.new, MockLog.new)

    volumes = provisioner.send(:collect_volumes)

    assert_equal 2, volumes.length

    db_vol = volumes.find { |v| v[:name].include?("database") }
    assert db_vol
    assert_equal "my-golang-app-master-1", db_vol[:server_name]
    assert_equal "/opt/nvoi/volumes/my-golang-app-master-database", db_vol[:mount_path]
    assert_equal 20, db_vol[:size]

    data_vol = volumes.find { |v| v[:name].end_with?("-data") }
    assert data_vol
    assert_equal 10, data_vol[:size]
  end

  def test_collect_volumes_empty_when_no_volumes
    config = build_config_without_volumes
    provisioner = Nvoi::Steps::VolumeProvisioner.new(config, MockProvider.new, MockLog.new)

    volumes = provisioner.send(:collect_volumes)

    assert_empty volumes
  end

  private

    def build_config_with_volumes
      VolumeTestConfig.new(
        servers: {
          "master" => VolumeTestServerConfig.new(
            volumes: {
              "database" => VolumeTestVolumeConfig.new(size: 20),
              "data" => VolumeTestVolumeConfig.new(size: 10)
            }
          )
        },
        app_name: "my-golang-app"
      )
    end

    def build_config_without_volumes
      VolumeTestConfig.new(
        servers: {
          "master" => VolumeTestServerConfig.new(volumes: {})
        },
        app_name: "my-golang-app"
      )
    end

    class VolumeTestConfig
      attr_reader :deploy, :namer

      def initialize(servers:, app_name:)
        @deploy = VolumeTestDeploy.new(servers, app_name)
        @namer = VolumeTestNamer.new(app_name)
      end
    end

    class VolumeTestDeploy
      attr_reader :application

      def initialize(servers, app_name)
        @application = VolumeTestApplication.new(servers, app_name)
      end
    end

    class VolumeTestApplication
      attr_reader :servers, :name

      def initialize(servers, name)
        @servers = servers
        @name = name
      end
    end

    class VolumeTestServerConfig
      attr_reader :volumes

      def initialize(volumes:)
        @volumes = volumes
      end
    end

    class VolumeTestVolumeConfig
      attr_reader :size

      def initialize(size:)
        @size = size
      end
    end

    class VolumeTestNamer
      def initialize(app_name)
        @app_name = app_name
      end

      def server_name(group, index)
        "#{@app_name}-#{group}-#{index}"
      end

      def server_volume_name(server_name, volume_name)
        "#{@app_name}-#{server_name}-#{volume_name}"
      end

      def server_volume_host_path(server_name, volume_name)
        "/opt/nvoi/volumes/#{server_volume_name(server_name, volume_name)}"
      end
    end

    class MockProvider
      def get_volume_by_name(_name)
        nil
      end
    end

    class MockLog
      def info(*); end
      def success(*); end
      def warning(*); end
      def error(*); end
    end
end
