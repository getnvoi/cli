# frozen_string_literal: true

require "test_helper"

class ConstantsTest < Minitest::Test
  def test_default_config_file
    assert_equal "deploy.enc", Nvoi::Utils::Constants::DEFAULT_CONFIG_FILE
  end

  def test_network_cidr
    assert_equal "10.0.0.0/16", Nvoi::Utils::Constants::NETWORK_CIDR
  end

  def test_default_image
    assert_equal "ubuntu-24.04", Nvoi::Utils::Constants::DEFAULT_IMAGE
  end

  def test_database_ports
    assert_equal 5432, Nvoi::Utils::Constants::DATABASE_PORTS["postgres"]
    assert_equal 3306, Nvoi::Utils::Constants::DATABASE_PORTS["mysql"]
    assert_equal 6379, Nvoi::Utils::Constants::DATABASE_PORTS["redis"]
  end

  def test_database_images
    assert_equal "postgres:15-alpine", Nvoi::Utils::Constants::DATABASE_IMAGES["postgres"]
    assert_equal "mysql:8.0", Nvoi::Utils::Constants::DATABASE_IMAGES["mysql"]
  end

  def test_k3s_version
    assert_match(/^v\d+\.\d+\.\d+/, Nvoi::Utils::Constants::DEFAULT_K3S_VERSION)
  end

  def test_registry_port
    assert_equal 30500, Nvoi::Utils::Constants::REGISTRY_PORT
  end

  def test_constants_frozen
    assert Nvoi::Utils::Constants::DATABASE_PORTS.frozen?
    assert Nvoi::Utils::Constants::DATABASE_IMAGES.frozen?
  end
end
