# frozen_string_literal: true

require "test_helper"

class Nvoi::Config::ResourceNamerTest < Minitest::Test
  def setup
    @config = mock_config
    @namer = Nvoi::Config::ResourceNamer.new(@config)
  end

  # ============================================================================
  # SERVER NAMES
  # ============================================================================

  def test_server_name_master
    assert_equal "myapp-master-1", @namer.server_name("master", 1)
  end

  def test_server_name_workers
    assert_equal "myapp-workers-3", @namer.server_name("workers", 3)
  end

  def test_server_name_custom_group
    assert_equal "myapp-custom-group-5", @namer.server_name("custom-group", 5)
  end

  # ============================================================================
  # FIREWALL AND NETWORK
  # ============================================================================

  def test_firewall_name
    assert_equal "testuser-testrepo-myapp-firewall", @namer.firewall_name
  end

  def test_network_name
    assert_equal "testuser-testrepo-myapp-network", @namer.network_name
  end

  def test_docker_network_name
    assert_equal "testuser-testrepo-myapp-docker-network", @namer.docker_network_name
  end

  # ============================================================================
  # DATABASE RESOURCES
  # ============================================================================

  def test_database_service_name
    assert_equal "db-myapp", @namer.database_service_name
  end

  def test_database_stateful_set_name
    assert_equal "db-myapp", @namer.database_stateful_set_name
  end

  def test_database_pvc_name
    assert_equal "data-db-myapp-0", @namer.database_pvc_name
  end

  def test_database_secret_name
    assert_equal "db-secret-myapp", @namer.database_secret_name
  end

  def test_database_pod_label
    assert_equal "app=db-myapp", @namer.database_pod_label
  end

  def test_database_volume_name
    assert_equal "myapp-db-data", @namer.database_volume_name
  end

  # ============================================================================
  # APP RESOURCES
  # ============================================================================

  def test_app_deployment_name
    assert_equal "myapp-web", @namer.app_deployment_name("web")
    assert_equal "myapp-worker", @namer.app_deployment_name("worker")
  end

  def test_app_service_name
    assert_equal "myapp-api", @namer.app_service_name("api")
  end

  def test_app_secret_name
    assert_equal "app-secret-myapp", @namer.app_secret_name
  end

  def test_app_pvc_name
    assert_equal "myapp-uploads", @namer.app_pvc_name("uploads")
  end

  def test_app_ingress_name
    assert_equal "myapp-web", @namer.app_ingress_name("web")
  end

  def test_app_pod_label
    assert_equal "app=myapp-web", @namer.app_pod_label("web")
  end

  def test_service_container_prefix
    assert_equal "testuser-testrepo-myapp-web-", @namer.service_container_prefix("web")
  end

  def test_app_volume_name
    assert_equal "myapp-app-web-uploads", @namer.app_volume_name("web", "uploads")
  end

  # ============================================================================
  # CLOUDFLARE RESOURCES
  # ============================================================================

  def test_tunnel_name
    assert_equal "testuser-testrepo-myapp-web", @namer.tunnel_name("web")
  end

  def test_cloudflared_deployment_name
    assert_equal "cloudflared-web", @namer.cloudflared_deployment_name("web")
  end

  # ============================================================================
  # REGISTRY RESOURCES
  # ============================================================================

  def test_registry_deployment_name
    assert_equal "nvoi-registry", @namer.registry_deployment_name
  end

  def test_registry_service_name
    assert_equal "nvoi-registry", @namer.registry_service_name
  end

  # ============================================================================
  # DEPLOYMENT RESOURCES
  # ============================================================================

  def test_deployment_lock_file_path
    assert_equal "/tmp/nvoi-deploy-testuser-testrepo-myapp.lock", @namer.deployment_lock_file_path
  end

  # ============================================================================
  # DOCKER IMAGE RESOURCES
  # ============================================================================

  def test_image_tag
    assert_equal "testuser-testrepo-myapp:20231215120000", @namer.image_tag("20231215120000")
  end

  def test_latest_image_tag
    assert_equal "testuser-testrepo-myapp:latest", @namer.latest_image_tag
  end

  # ============================================================================
  # VOLUME RESOURCES
  # ============================================================================

  def test_volume_name
    assert_equal "myapp-app-web-uploads", @namer.volume_name("app", "web", "uploads")
    assert_equal "myapp-svc-redis-data", @namer.volume_name("svc", "redis", "data")
  end

  def test_service_volume_name
    assert_equal "myapp-svc-redis-data", @namer.service_volume_name("redis", "data")
  end
end

class Nvoi::Config::ResourceNamerContainerPrefixTest < Minitest::Test
  def test_infer_container_prefix_with_app_name
    config = mock_config
    namer = Nvoi::Config::ResourceNamer.new(config)

    # Since we can't easily mock git, just verify it doesn't crash
    prefix = namer.infer_container_prefix
    assert_kind_of String, prefix
    assert prefix.length <= 63
  end

  def test_infer_container_prefix_truncates_long_names
    config = mock_config(
      deploy: mock_deploy_config(
        application: mock_application_config(name: "a" * 100)
      )
    )
    namer = Nvoi::Config::ResourceNamer.new(config)

    prefix = namer.infer_container_prefix
    assert prefix.length <= 63
  end
end
