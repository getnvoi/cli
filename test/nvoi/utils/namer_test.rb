# frozen_string_literal: true

require "test_helper"

class NamerTest < Minitest::Test
  # Mock config for testing
  MockConfig = Struct.new(:deploy, :container_prefix, keyword_init: true)
  MockDeploy = Struct.new(:application, keyword_init: true)
  MockApplication = Struct.new(:name, keyword_init: true)

  def setup
    app = MockApplication.new(name: "myapp")
    deploy = MockDeploy.new(application: app)
    @config = MockConfig.new(deploy: deploy, container_prefix: "user-repo-myapp")
    @namer = Nvoi::Utils::ResourceNamer.new(@config)
  end

  def test_server_name
    assert_equal "myapp-master-1", @namer.server_name("master", 1)
    assert_equal "myapp-workers-3", @namer.server_name("workers", 3)
  end

  def test_firewall_name
    assert_equal "user-repo-myapp-firewall", @namer.firewall_name
  end

  def test_network_name
    assert_equal "user-repo-myapp-network", @namer.network_name
  end

  def test_docker_network_name
    assert_equal "user-repo-myapp-docker-network", @namer.docker_network_name
  end

  def test_database_service_name
    assert_equal "db-myapp", @namer.database_service_name
  end

  def test_database_pod_name
    assert_equal "db-myapp-0", @namer.database_pod_name
  end

  def test_database_pvc_name
    assert_equal "data-db-myapp-0", @namer.database_pvc_name
  end

  def test_database_secret_name
    assert_equal "db-secret-myapp", @namer.database_secret_name
  end

  def test_app_deployment_name
    assert_equal "myapp-web", @namer.app_deployment_name("web")
    assert_equal "myapp-worker", @namer.app_deployment_name("worker")
  end

  def test_app_service_name
    assert_equal "myapp-web", @namer.app_service_name("web")
  end

  def test_app_secret_name
    assert_equal "app-secret-myapp", @namer.app_secret_name
  end

  def test_app_pvc_name
    assert_equal "myapp-data", @namer.app_pvc_name("data")
  end

  def test_tunnel_name
    assert_equal "user-repo-myapp-web", @namer.tunnel_name("web")
  end

  def test_cloudflared_deployment_name
    assert_equal "cloudflared-web", @namer.cloudflared_deployment_name("web")
  end

  def test_image_tag
    assert_equal "user-repo-myapp:20240115120000", @namer.image_tag("20240115120000")
  end

  def test_latest_image_tag
    assert_equal "user-repo-myapp:latest", @namer.latest_image_tag
  end

  def test_server_volume_name
    assert_equal "myapp-master-1-database", @namer.server_volume_name("master-1", "database")
  end

  def test_server_volume_host_path
    assert_equal "/opt/nvoi/volumes/myapp-master-1-database", @namer.server_volume_host_path("master-1", "database")
  end

  def test_hostname_with_subdomain
    assert_equal "app.example.com", @namer.hostname("app", "example.com")
  end

  def test_hostname_without_subdomain
    assert_equal "example.com", @namer.hostname(nil, "example.com")
    assert_equal "example.com", @namer.hostname("", "example.com")
  end

  def test_registry_names
    assert_equal "nvoi-registry", @namer.registry_deployment_name
    assert_equal "nvoi-registry", @namer.registry_service_name
  end
end
