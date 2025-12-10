# frozen_string_literal: true

require "test_helper"
require "ostruct"

class Nvoi::Service::DeleteServiceTest < Minitest::Test
  # Test that collect_volume_names uses correct field names after volume->mount rename

  def test_database_config_uses_mount_not_volume
    db = Nvoi::Config::DatabaseConfig.new({
      "servers" => ["master"],
      "adapter" => "postgres",
      "mount" => { "db" => "/var/lib/postgresql/data" }
    })

    # mount should exist and work
    assert_respond_to db, :mount
    assert_equal({ "db" => "/var/lib/postgresql/data" }, db.mount)

    # volume should NOT exist
    refute_respond_to db, :volume, "DatabaseConfig should use 'mount' not 'volume'"
  end

  def test_service_config_uses_mount_not_volume
    svc = Nvoi::Config::ServiceConfig.new({
      "servers" => ["master"],
      "image" => "redis:alpine",
      "mount" => { "data" => "/data" }
    })

    # mount should exist and work
    assert_respond_to svc, :mount
    assert_equal({ "data" => "/data" }, svc.mount)

    # volume should NOT exist
    refute_respond_to svc, :volume, "ServiceConfig should use 'mount' not 'volume'"
  end

  def test_app_service_config_uses_mounts_not_volumes
    app = Nvoi::Config::AppServiceConfig.new({
      "servers" => ["master"],
      "port" => 3000,
      "mounts" => { "uploads" => "/app/uploads" }
    })

    # mounts should exist and work
    assert_respond_to app, :mounts
    assert_equal({ "uploads" => "/app/uploads" }, app.mounts)

    # volumes should NOT exist
    refute_respond_to app, :volumes, "AppServiceConfig should use 'mounts' not 'volumes'"
  end

  # Test that calling old field names raises NoMethodError
  # This simulates what delete.rb does and should fail

  def test_calling_volume_on_database_config_raises
    db = Nvoi::Config::DatabaseConfig.new({
      "servers" => ["master"],
      "adapter" => "sqlite3"
    })

    # This is what delete.rb line 133 does - it should raise NoMethodError
    assert_raises(NoMethodError) { db.volume }
  end

  def test_calling_volume_on_service_config_raises
    svc = Nvoi::Config::ServiceConfig.new({
      "servers" => ["master"],
      "image" => "redis:alpine"
    })

    # This is what delete.rb line 137 does - it should raise NoMethodError
    assert_raises(NoMethodError) { svc.volume }
  end

  def test_calling_volumes_on_app_service_config_raises
    app = Nvoi::Config::AppServiceConfig.new({
      "servers" => ["master"],
      "port" => 3000
    })

    # This is what delete.rb line 142 does - it should raise NoMethodError
    assert_raises(NoMethodError) { app.volumes }
  end

  # Test that old naming methods don't exist (volume redesign replaced them)

  def test_namer_uses_server_volume_name_not_database_volume_name
    namer = MockNamer.new

    # New method should exist
    assert_respond_to namer, :server_volume_name

    # Old methods should NOT exist (delete.rb line 133 uses database_volume_name)
    refute_respond_to namer, :database_volume_name, "Namer should use server_volume_name not database_volume_name"
  end

  def test_namer_uses_server_volume_name_not_service_volume_name
    namer = MockNamer.new

    # Old method should NOT exist (delete.rb line 137 uses service_volume_name)
    refute_respond_to namer, :service_volume_name, "Namer should use server_volume_name not service_volume_name"
  end

  def test_namer_uses_server_volume_name_not_app_volume_name
    namer = MockNamer.new

    # Old method should NOT exist (delete.rb line 145 uses app_volume_name)
    refute_respond_to namer, :app_volume_name, "Namer should use server_volume_name not app_volume_name"
  end

  private

    # Use real namer to test method existence
    class MockNamer < Nvoi::Config::ResourceNamer
      def initialize
        # Create minimal config for namer
        @config = OpenStruct.new(
          deploy: OpenStruct.new(
            application: OpenStruct.new(name: "test")
          ),
          container_prefix: "test"
        )
      end
    end
end
