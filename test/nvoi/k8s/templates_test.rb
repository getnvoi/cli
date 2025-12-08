# frozen_string_literal: true

require "test_helper"

class Nvoi::K8s::TemplatesTest < Minitest::Test
  def test_template_names_returns_all_templates
    names = Nvoi::K8s::Templates.template_names

    assert_includes names, "app-deployment.yaml"
    assert_includes names, "app-secret.yaml"
    assert_includes names, "app-service.yaml"
    assert_includes names, "db-statefulset.yaml"
    assert_includes names, "service-deployment.yaml"
    assert_includes names, "worker-deployment.yaml"
  end

  def test_load_template_returns_erb
    template = Nvoi::K8s::Templates.load_template("app-secret.yaml")
    assert_instance_of ERB, template
  end

  def test_load_template_raises_for_missing
    assert_raises(Nvoi::TemplateError) do
      Nvoi::K8s::Templates.load_template("nonexistent")
    end
  end
end

class Nvoi::K8s::RendererAppDeploymentTest < Minitest::Test
  # ============================================================================
  # APP DEPLOYMENT TEMPLATE - ALL POSSIBILITIES
  # ============================================================================

  def test_minimal_app_deployment
    yaml = Nvoi::K8s::Renderer.render_template("app-deployment.yaml", {
      name: "myapp-web",
      replicas: 1,
      image: "registry:5000/myapp:latest",
      secret_name: "app-secret-myapp",
      env_keys: ["DATABASE_URL"],
      resources: { request_memory: "128Mi", request_cpu: "100m", limit_memory: "256Mi", limit_cpu: "200m" },
      affinity_server_names: nil,
      command: nil,
      port: nil,
      readiness_probe: nil,
      liveness_probe: nil,
      volume_mounts: nil,
      host_path_volumes: nil,
      volumes: nil
    })

    assert valid_yaml?(yaml), "Generated YAML is invalid"
    doc = YAML.safe_load(yaml)

    assert_equal "apps/v1", doc["apiVersion"]
    assert_equal "Deployment", doc["kind"]
    assert_equal "myapp-web", doc["metadata"]["name"]
    assert_equal 1, doc["spec"]["replicas"]
    assert_equal "registry:5000/myapp:latest", doc["spec"]["template"]["spec"]["containers"][0]["image"]
    assert_nil doc["spec"]["template"]["spec"]["affinity"]
    assert_nil doc["spec"]["template"]["spec"]["containers"][0]["command"]
    assert_nil doc["spec"]["template"]["spec"]["containers"][0]["ports"]
    assert_nil doc["spec"]["template"]["spec"]["containers"][0]["readinessProbe"]
    assert_nil doc["spec"]["template"]["spec"]["containers"][0]["livenessProbe"]
    assert_nil doc["spec"]["template"]["spec"]["containers"][0]["volumeMounts"]
    assert_nil doc["spec"]["template"]["spec"]["volumes"]
  end

  def test_app_deployment_with_affinity
    yaml = Nvoi::K8s::Renderer.render_template("app-deployment.yaml", {
      name: "myapp-web",
      replicas: 2,
      image: "registry:5000/myapp:v1",
      secret_name: "app-secret-myapp",
      env_keys: ["DATABASE_URL", "REDIS_URL"],
      resources: { request_memory: "256Mi", request_cpu: "200m", limit_memory: "512Mi", limit_cpu: "500m" },
      affinity_server_names: ["master", "workers"],
      command: nil,
      port: nil,
      readiness_probe: nil,
      liveness_probe: nil,
      volume_mounts: nil,
      host_path_volumes: nil,
      volumes: nil
    })

    assert valid_yaml?(yaml)
    doc = YAML.safe_load(yaml)

    affinity = doc.dig("spec", "template", "spec", "affinity")
    refute_nil affinity
    node_selector = affinity.dig("nodeAffinity", "requiredDuringSchedulingIgnoredDuringExecution", "nodeSelectorTerms", 0)
    refute_nil node_selector

    expressions = node_selector["matchExpressions"]
    assert_equal 1, expressions.length
    assert_equal "nvoi.io/server-name", expressions[0]["key"]
    assert_equal "In", expressions[0]["operator"]
    assert_includes expressions[0]["values"], "master"
    assert_includes expressions[0]["values"], "workers"
  end

  def test_app_deployment_with_command
    yaml = Nvoi::K8s::Renderer.render_template("app-deployment.yaml", {
      name: "myapp-web",
      replicas: 1,
      image: "registry:5000/myapp:latest",
      secret_name: "app-secret-myapp",
      env_keys: ["DATABASE_URL"],
      resources: { request_memory: "128Mi", request_cpu: "100m", limit_memory: "256Mi", limit_cpu: "200m" },
      affinity_server_names: nil,
      command: ["/bin/sh", "-c", "bundle exec rails server -p 3000"],
      port: nil,
      readiness_probe: nil,
      liveness_probe: nil,
      volume_mounts: nil,
      host_path_volumes: nil,
      volumes: nil
    })

    assert valid_yaml?(yaml)
    doc = YAML.safe_load(yaml)

    container = doc.dig("spec", "template", "spec", "containers", 0)
    assert_equal 3, container["command"].length
    assert_equal "/bin/sh", container["command"][0]
    assert_equal "-c", container["command"][1]
    assert_equal "bundle exec rails server -p 3000", container["command"][2]
  end

  def test_app_deployment_with_port
    yaml = Nvoi::K8s::Renderer.render_template("app-deployment.yaml", {
      name: "myapp-web",
      replicas: 1,
      image: "registry:5000/myapp:latest",
      secret_name: "app-secret-myapp",
      env_keys: ["DATABASE_URL"],
      resources: { request_memory: "128Mi", request_cpu: "100m", limit_memory: "256Mi", limit_cpu: "200m" },
      affinity_server_names: nil,
      command: nil,
      port: 3000,
      readiness_probe: nil,
      liveness_probe: nil,
      volume_mounts: nil,
      host_path_volumes: nil,
      volumes: nil
    })

    assert valid_yaml?(yaml)
    doc = YAML.safe_load(yaml)

    ports = doc.dig("spec", "template", "spec", "containers", 0, "ports")
    assert_equal 1, ports.length
    assert_equal 3000, ports[0]["containerPort"]
  end

  def test_app_deployment_with_readiness_probe
    yaml = Nvoi::K8s::Renderer.render_template("app-deployment.yaml", {
      name: "myapp-web",
      replicas: 1,
      image: "registry:5000/myapp:latest",
      secret_name: "app-secret-myapp",
      env_keys: ["DATABASE_URL"],
      resources: { request_memory: "128Mi", request_cpu: "100m", limit_memory: "256Mi", limit_cpu: "200m" },
      affinity_server_names: nil,
      command: nil,
      port: 3000,
      readiness_probe: { path: "/health", port: 3000, initial_delay: 5, period: 10, timeout: 3, failure_threshold: 3 },
      liveness_probe: nil,
      volume_mounts: nil,
      host_path_volumes: nil,
      volumes: nil
    })

    assert valid_yaml?(yaml)
    doc = YAML.safe_load(yaml)

    probe = doc.dig("spec", "template", "spec", "containers", 0, "readinessProbe")
    refute_nil probe
    assert_equal "/health", probe.dig("httpGet", "path")
    assert_equal 3000, probe.dig("httpGet", "port")
    assert_equal 5, probe["initialDelaySeconds"]
    assert_equal 10, probe["periodSeconds"]
    assert_equal 3, probe["timeoutSeconds"]
    assert_equal 3, probe["failureThreshold"]
  end

  def test_app_deployment_with_liveness_probe
    yaml = Nvoi::K8s::Renderer.render_template("app-deployment.yaml", {
      name: "myapp-web",
      replicas: 1,
      image: "registry:5000/myapp:latest",
      secret_name: "app-secret-myapp",
      env_keys: ["DATABASE_URL"],
      resources: { request_memory: "128Mi", request_cpu: "100m", limit_memory: "256Mi", limit_cpu: "200m" },
      affinity_server_names: nil,
      command: nil,
      port: 3000,
      readiness_probe: nil,
      liveness_probe: { path: "/ping", port: 3000, initial_delay: 30, period: 15, timeout: 5, failure_threshold: 5 },
      volume_mounts: nil,
      host_path_volumes: nil,
      volumes: nil
    })

    assert valid_yaml?(yaml)
    doc = YAML.safe_load(yaml)

    probe = doc.dig("spec", "template", "spec", "containers", 0, "livenessProbe")
    refute_nil probe
    assert_equal "/ping", probe.dig("httpGet", "path")
    assert_equal 30, probe["initialDelaySeconds"]
  end

  def test_app_deployment_with_both_probes
    yaml = Nvoi::K8s::Renderer.render_template("app-deployment.yaml", {
      name: "myapp-web",
      replicas: 1,
      image: "registry:5000/myapp:latest",
      secret_name: "app-secret-myapp",
      env_keys: ["DATABASE_URL"],
      resources: { request_memory: "128Mi", request_cpu: "100m", limit_memory: "256Mi", limit_cpu: "200m" },
      affinity_server_names: nil,
      command: nil,
      port: 3000,
      readiness_probe: { path: "/ready", port: 3000, initial_delay: 5, period: 10, timeout: 3, failure_threshold: 3 },
      liveness_probe: { path: "/live", port: 3000, initial_delay: 15, period: 20, timeout: 5, failure_threshold: 3 },
      volume_mounts: nil,
      host_path_volumes: nil,
      volumes: nil
    })

    assert valid_yaml?(yaml)
    doc = YAML.safe_load(yaml)

    container = doc.dig("spec", "template", "spec", "containers", 0)
    assert_equal "/ready", container.dig("readinessProbe", "httpGet", "path")
    assert_equal "/live", container.dig("livenessProbe", "httpGet", "path")
  end

  def test_app_deployment_with_volume_mounts
    yaml = Nvoi::K8s::Renderer.render_template("app-deployment.yaml", {
      name: "myapp-web",
      replicas: 1,
      image: "registry:5000/myapp:latest",
      secret_name: "app-secret-myapp",
      env_keys: ["DATABASE_URL"],
      resources: { request_memory: "128Mi", request_cpu: "100m", limit_memory: "256Mi", limit_cpu: "200m" },
      affinity_server_names: nil,
      command: nil,
      port: nil,
      readiness_probe: nil,
      liveness_probe: nil,
      volume_mounts: [
        { name: "uploads", mount_path: "/app/public/uploads" },
        { name: "cache", mount_path: "/app/tmp/cache" }
      ],
      host_path_volumes: nil,
      volumes: nil
    })

    assert valid_yaml?(yaml)
    doc = YAML.safe_load(yaml)

    mounts = doc.dig("spec", "template", "spec", "containers", 0, "volumeMounts")
    assert_equal 2, mounts.length
    assert_equal "uploads", mounts[0]["name"]
    assert_equal "/app/public/uploads", mounts[0]["mountPath"]
    assert_equal "cache", mounts[1]["name"]
  end

  def test_app_deployment_with_host_path_volumes
    yaml = Nvoi::K8s::Renderer.render_template("app-deployment.yaml", {
      name: "myapp-web",
      replicas: 1,
      image: "registry:5000/myapp:latest",
      secret_name: "app-secret-myapp",
      env_keys: ["DATABASE_URL"],
      resources: { request_memory: "128Mi", request_cpu: "100m", limit_memory: "256Mi", limit_cpu: "200m" },
      affinity_server_names: nil,
      command: nil,
      port: nil,
      readiness_probe: nil,
      liveness_probe: nil,
      volume_mounts: [{ name: "data", mount_path: "/data" }],
      host_path_volumes: [{ name: "data", host_path: "/mnt/data" }],
      volumes: nil
    })

    assert valid_yaml?(yaml)
    doc = YAML.safe_load(yaml)

    vols = doc.dig("spec", "template", "spec", "volumes")
    assert_equal 1, vols.length
    assert_equal "data", vols[0]["name"]
    assert_equal "/mnt/data", vols[0].dig("hostPath", "path")
    assert_equal "DirectoryOrCreate", vols[0].dig("hostPath", "type")
  end

  def test_app_deployment_with_pvc_volumes
    yaml = Nvoi::K8s::Renderer.render_template("app-deployment.yaml", {
      name: "myapp-web",
      replicas: 1,
      image: "registry:5000/myapp:latest",
      secret_name: "app-secret-myapp",
      env_keys: ["DATABASE_URL"],
      resources: { request_memory: "128Mi", request_cpu: "100m", limit_memory: "256Mi", limit_cpu: "200m" },
      affinity_server_names: nil,
      command: nil,
      port: nil,
      readiness_probe: nil,
      liveness_probe: nil,
      volume_mounts: [{ name: "uploads", mount_path: "/app/uploads" }],
      host_path_volumes: nil,
      volumes: [{ name: "uploads", claim_name: "myapp-uploads-pvc" }]
    })

    assert valid_yaml?(yaml)
    doc = YAML.safe_load(yaml)

    vols = doc.dig("spec", "template", "spec", "volumes")
    assert_equal 1, vols.length
    assert_equal "uploads", vols[0]["name"]
    assert_equal "myapp-uploads-pvc", vols[0].dig("persistentVolumeClaim", "claimName")
  end

  def test_app_deployment_with_mixed_volumes
    yaml = Nvoi::K8s::Renderer.render_template("app-deployment.yaml", {
      name: "myapp-web",
      replicas: 1,
      image: "registry:5000/myapp:latest",
      secret_name: "app-secret-myapp",
      env_keys: ["DATABASE_URL"],
      resources: { request_memory: "128Mi", request_cpu: "100m", limit_memory: "256Mi", limit_cpu: "200m" },
      affinity_server_names: nil,
      command: nil,
      port: nil,
      readiness_probe: nil,
      liveness_probe: nil,
      volume_mounts: [
        { name: "logs", mount_path: "/var/log/app" },
        { name: "data", mount_path: "/data" }
      ],
      host_path_volumes: [{ name: "logs", host_path: "/var/log/host-app" }],
      volumes: [{ name: "data", claim_name: "data-pvc" }]
    })

    assert valid_yaml?(yaml)
    doc = YAML.safe_load(yaml)

    vols = doc.dig("spec", "template", "spec", "volumes")
    assert_equal 2, vols.length

    log_vol = vols.find { |v| v["name"] == "logs" }
    data_vol = vols.find { |v| v["name"] == "data" }

    refute_nil log_vol["hostPath"]
    refute_nil data_vol["persistentVolumeClaim"]
  end

  def test_app_deployment_full_featured
    yaml = Nvoi::K8s::Renderer.render_template("app-deployment.yaml", {
      name: "production-web",
      replicas: 3,
      image: "registry:5000/myapp:20231215120000",
      secret_name: "app-secret-production",
      env_keys: ["DATABASE_URL", "REDIS_URL", "SECRET_KEY_BASE", "RAILS_ENV"],
      resources: { request_memory: "512Mi", request_cpu: "500m", limit_memory: "1Gi", limit_cpu: "1000m" },
      affinity_server_names: ["workers"],
      command: ["/bin/sh", "-c", "bundle exec puma -C config/puma.rb"],
      port: 3000,
      readiness_probe: { path: "/health", port: 3000, initial_delay: 10, period: 5, timeout: 3, failure_threshold: 3 },
      liveness_probe: { path: "/health", port: 3000, initial_delay: 30, period: 10, timeout: 5, failure_threshold: 5 },
      volume_mounts: [
        { name: "uploads", mount_path: "/app/public/uploads" },
        { name: "tmp", mount_path: "/app/tmp" }
      ],
      host_path_volumes: [{ name: "tmp", host_path: "/tmp/app-cache" }],
      volumes: [{ name: "uploads", claim_name: "uploads-pvc" }]
    })

    assert valid_yaml?(yaml)
    doc = YAML.safe_load(yaml)

    # Verify all features are present
    assert_equal 3, doc["spec"]["replicas"]

    container = doc.dig("spec", "template", "spec", "containers", 0)
    assert_equal 3, container["command"].length
    assert_equal 3000, container["ports"][0]["containerPort"]
    refute_nil container["readinessProbe"]
    refute_nil container["livenessProbe"]
    assert_equal 4, container["env"].length
    assert_equal 2, container["volumeMounts"].length

    refute_nil doc.dig("spec", "template", "spec", "affinity")
    assert_equal 2, doc.dig("spec", "template", "spec", "volumes").length
  end

  def test_app_deployment_with_multiple_env_vars
    yaml = Nvoi::K8s::Renderer.render_template("app-deployment.yaml", {
      name: "myapp-web",
      replicas: 1,
      image: "registry:5000/myapp:latest",
      secret_name: "app-secret-myapp",
      env_keys: ["DB_HOST", "DB_USER", "DB_PASS", "REDIS_URL", "MEMCACHE_URL", "SECRET_KEY"],
      resources: { request_memory: "128Mi", request_cpu: "100m", limit_memory: "256Mi", limit_cpu: "200m" },
      affinity_server_names: nil,
      command: nil,
      port: nil,
      readiness_probe: nil,
      liveness_probe: nil,
      volume_mounts: nil,
      host_path_volumes: nil,
      volumes: nil
    })

    assert valid_yaml?(yaml)
    doc = YAML.safe_load(yaml)

    env_vars = doc.dig("spec", "template", "spec", "containers", 0, "env")
    assert_equal 6, env_vars.length

    env_names = env_vars.map { |e| e["name"] }
    assert_includes env_names, "DB_HOST"
    assert_includes env_names, "SECRET_KEY"

    env_vars.each do |env|
      assert_equal "app-secret-myapp", env.dig("valueFrom", "secretKeyRef", "name")
    end
  end
end

class Nvoi::K8s::RendererAppSecretTest < Minitest::Test
  # ============================================================================
  # APP SECRET TEMPLATE - ALL POSSIBILITIES
  # ============================================================================

  def test_app_secret_single_env_var
    yaml = Nvoi::K8s::Renderer.render_template("app-secret.yaml", {
      name: "app-secret-myapp",
      env_vars: { "DATABASE_URL" => "postgres://localhost/myapp" }
    })

    assert valid_yaml?(yaml)
    doc = YAML.safe_load(yaml)

    assert_equal "v1", doc["apiVersion"]
    assert_equal "Secret", doc["kind"]
    assert_equal "app-secret-myapp", doc["metadata"]["name"]
    assert_equal "Opaque", doc["type"]
    # Template uses .inspect which adds quotes to the string value
    assert_equal "postgres://localhost/myapp", doc["stringData"]["DATABASE_URL"]
  end

  def test_app_secret_multiple_env_vars
    yaml = Nvoi::K8s::Renderer.render_template("app-secret.yaml", {
      name: "app-secret-myapp",
      env_vars: {
        "DATABASE_URL" => "postgres://localhost/myapp",
        "REDIS_URL" => "redis://localhost:6379",
        "SECRET_KEY_BASE" => "abc123xyz",
        "RAILS_ENV" => "production"
      }
    })

    assert valid_yaml?(yaml)
    doc = YAML.safe_load(yaml)

    assert_equal 4, doc["stringData"].keys.length
    assert_includes doc["stringData"].keys, "DATABASE_URL"
    assert_includes doc["stringData"].keys, "REDIS_URL"
    assert_includes doc["stringData"].keys, "SECRET_KEY_BASE"
    assert_includes doc["stringData"].keys, "RAILS_ENV"
  end

  def test_app_secret_special_characters
    yaml = Nvoi::K8s::Renderer.render_template("app-secret.yaml", {
      name: "app-secret-myapp",
      env_vars: {
        "API_KEY" => "sk_test_abc123",
        "DB_PASSWORD" => "password_with_numbers_42",
        "JSON_CONFIG" => '{"key":"value"}'
      }
    })

    assert valid_yaml?(yaml), "Generated YAML: #{yaml}"
    doc = YAML.safe_load(yaml)

    assert_equal 3, doc["stringData"].keys.length
    assert_equal "sk_test_abc123", doc["stringData"]["API_KEY"]
  end

  def test_app_secret_empty_value
    yaml = Nvoi::K8s::Renderer.render_template("app-secret.yaml", {
      name: "app-secret-myapp",
      env_vars: { "EMPTY_VAR" => "" }
    })

    assert valid_yaml?(yaml)
    doc = YAML.safe_load(yaml)

    # Template uses .inspect: "".inspect => '""' which YAML parses as empty string
    assert_equal "", doc["stringData"]["EMPTY_VAR"]
  end
end

class Nvoi::K8s::RendererAppServiceTest < Minitest::Test
  # ============================================================================
  # APP SERVICE TEMPLATE - ALL POSSIBILITIES
  # ============================================================================

  def test_app_service_basic
    yaml = Nvoi::K8s::Renderer.render_template("app-service.yaml", {
      name: "myapp-web",
      port: 3000
    })

    assert valid_yaml?(yaml)
    doc = YAML.safe_load(yaml)

    assert_equal "v1", doc["apiVersion"]
    assert_equal "Service", doc["kind"]
    assert_equal "myapp-web", doc["metadata"]["name"]
    assert_equal "default", doc["metadata"]["namespace"]
    assert_equal "ClusterIP", doc["spec"]["type"]
    assert_equal 3000, doc["spec"]["ports"][0]["port"]
    assert_equal 3000, doc["spec"]["ports"][0]["targetPort"]
    assert_equal "myapp-web", doc["spec"]["selector"]["app"]
  end

  def test_app_service_different_ports
    yaml = Nvoi::K8s::Renderer.render_template("app-service.yaml", {
      name: "api-service",
      port: 8080
    })

    assert valid_yaml?(yaml)
    doc = YAML.safe_load(yaml)

    assert_equal 8080, doc["spec"]["ports"][0]["port"]
    assert_equal 8080, doc["spec"]["ports"][0]["targetPort"]
  end
end

class Nvoi::K8s::RendererDbStatefulsetTest < Minitest::Test
  # ============================================================================
  # DATABASE STATEFULSET TEMPLATE - ALL POSSIBILITIES
  # ============================================================================

  def test_db_statefulset_with_host_path
    yaml = Nvoi::K8s::Renderer.render_template("db-statefulset.yaml", {
      service_name: "db-myapp",
      adapter: "postgres",
      image: "postgres:15",
      secret_name: "db-secret-myapp",
      secret_keys: ["POSTGRES_USER", "POSTGRES_PASSWORD", "POSTGRES_DB"],
      port: 5432,
      data_path: "/var/lib/postgresql/data",
      host_path: "/mnt/volume/db-data",
      storage_size: nil,
      affinity_server_names: nil
    })

    docs = parse_yaml_docs(yaml)
    statefulset = docs[0]
    service = docs[1]

    assert_equal "apps/v1", statefulset["apiVersion"]
    assert_equal "StatefulSet", statefulset["kind"]
    assert_equal "db-myapp", statefulset["metadata"]["name"]

    container = statefulset.dig("spec", "template", "spec", "containers", 0)
    assert_equal "postgres", container["name"]
    assert_equal "postgres:15", container["image"]
    assert_equal 3, container["env"].length - 1 # -1 for PGDATA

    # Should have hostPath volume, not volumeClaimTemplates
    volumes = statefulset.dig("spec", "template", "spec", "volumes")
    refute_nil volumes
    assert_equal "/mnt/volume/db-data", volumes[0].dig("hostPath", "path")
    assert_nil statefulset.dig("spec", "volumeClaimTemplates")

    # Verify service
    assert_equal "v1", service["apiVersion"]
    assert_equal "Service", service["kind"]
    assert_equal "db-myapp", service["metadata"]["name"]
    assert_equal "None", service["spec"]["clusterIP"] # headless service
    assert_equal 5432, service["spec"]["ports"][0]["port"]
  end

  def test_db_statefulset_with_pvc
    yaml = Nvoi::K8s::Renderer.render_template("db-statefulset.yaml", {
      service_name: "db-myapp",
      adapter: "postgres",
      image: "postgres:15",
      secret_name: "db-secret-myapp",
      secret_keys: ["POSTGRES_USER", "POSTGRES_PASSWORD"],
      port: 5432,
      data_path: "/var/lib/postgresql/data",
      host_path: nil,
      storage_size: "10Gi",
      affinity_server_names: nil
    })

    docs = parse_yaml_docs(yaml)
    statefulset = docs[0]

    # Should have volumeClaimTemplates, not hostPath
    assert_nil statefulset.dig("spec", "template", "spec", "volumes")

    vct = statefulset.dig("spec", "volumeClaimTemplates")
    refute_nil vct
    assert_equal 1, vct.length
    assert_equal "data", vct[0]["metadata"]["name"]
    assert_equal ["ReadWriteOnce"], vct[0]["spec"]["accessModes"]
    assert_equal "10Gi", vct[0].dig("spec", "resources", "requests", "storage")
  end

  def test_db_statefulset_with_affinity
    yaml = Nvoi::K8s::Renderer.render_template("db-statefulset.yaml", {
      service_name: "db-myapp",
      adapter: "postgres",
      image: "postgres:15",
      secret_name: "db-secret-myapp",
      secret_keys: ["POSTGRES_USER", "POSTGRES_PASSWORD"],
      port: 5432,
      data_path: "/var/lib/postgresql/data",
      host_path: "/mnt/db",
      storage_size: nil,
      affinity_server_names: ["master"]
    })

    docs = parse_yaml_docs(yaml)
    statefulset = docs[0]

    affinity = statefulset.dig("spec", "template", "spec", "affinity")
    refute_nil affinity

    values = affinity.dig("nodeAffinity", "requiredDuringSchedulingIgnoredDuringExecution", "nodeSelectorTerms", 0, "matchExpressions", 0, "values")
    assert_includes values, "master"
  end

  def test_db_statefulset_mysql
    yaml = Nvoi::K8s::Renderer.render_template("db-statefulset.yaml", {
      service_name: "db-myapp",
      adapter: "mysql",
      image: "mysql:8",
      secret_name: "db-secret-myapp",
      secret_keys: ["MYSQL_ROOT_PASSWORD", "MYSQL_DATABASE"],
      port: 3306,
      data_path: "/var/lib/mysql",
      host_path: "/mnt/mysql-data",
      storage_size: nil,
      affinity_server_names: nil
    })

    docs = parse_yaml_docs(yaml)
    statefulset = docs[0]
    service = docs[1]

    container = statefulset.dig("spec", "template", "spec", "containers", 0)
    assert_equal "mysql", container["name"]
    assert_equal "mysql:8", container["image"]
    assert_equal 3306, container["ports"][0]["containerPort"]
    assert_equal "/var/lib/mysql", container["volumeMounts"][0]["mountPath"]

    assert_equal 3306, service["spec"]["ports"][0]["port"]
  end
end

class Nvoi::K8s::RendererServiceDeploymentTest < Minitest::Test
  # ============================================================================
  # SERVICE DEPLOYMENT TEMPLATE - ALL POSSIBILITIES
  # ============================================================================

  def test_service_deployment_minimal
    yaml = Nvoi::K8s::Renderer.render_template("service-deployment.yaml", {
      name: "redis",
      image: "redis:7",
      env_vars: {},
      env_keys: [],
      port: nil,
      command: nil,
      volume_path: nil,
      host_path: nil,
      affinity_server_names: nil
    })

    docs = parse_yaml_docs(yaml)
    secret = docs[0]
    deployment = docs[1]

    assert_equal "Secret", secret["kind"]
    assert_equal "redis-secret", secret["metadata"]["name"]

    assert_equal "Deployment", deployment["kind"]
    assert_equal "redis", deployment["metadata"]["name"]
    assert_equal "redis:7", deployment.dig("spec", "template", "spec", "containers", 0, "image")

    container = deployment.dig("spec", "template", "spec", "containers", 0)
    assert_nil container["ports"]
    assert_nil container["command"]
    assert_nil container["volumeMounts"]
    assert_nil deployment.dig("spec", "template", "spec", "volumes")
  end

  def test_service_deployment_with_port
    yaml = Nvoi::K8s::Renderer.render_template("service-deployment.yaml", {
      name: "redis",
      image: "redis:7",
      env_vars: {},
      env_keys: [],
      port: 6379,
      command: nil,
      volume_path: nil,
      host_path: nil,
      affinity_server_names: nil
    })

    docs = parse_yaml_docs(yaml)
    deployment = docs[1]
    service = docs[2]

    container = deployment.dig("spec", "template", "spec", "containers", 0)
    assert_equal 6379, container["ports"][0]["containerPort"]

    assert_equal "Service", service["kind"]
    assert_equal "redis", service["metadata"]["name"]
    assert_equal 6379, service["spec"]["ports"][0]["port"]
    assert_equal "ClusterIP", service["spec"]["type"]
  end

  def test_service_deployment_with_command
    yaml = Nvoi::K8s::Renderer.render_template("service-deployment.yaml", {
      name: "redis",
      image: "redis:7",
      env_vars: {},
      env_keys: [],
      port: 6379,
      command: ["redis-server", "--maxmemory", "256mb"],
      volume_path: nil,
      host_path: nil,
      affinity_server_names: nil
    })

    docs = parse_yaml_docs(yaml)
    deployment = docs[1]

    container = deployment.dig("spec", "template", "spec", "containers", 0)
    assert_equal 3, container["command"].length
    assert_equal "redis-server", container["command"][0]
  end

  def test_service_deployment_with_env_vars
    yaml = Nvoi::K8s::Renderer.render_template("service-deployment.yaml", {
      name: "redis",
      image: "redis:7",
      env_vars: { "REDIS_PASSWORD" => "secret123" },
      env_keys: ["REDIS_PASSWORD"],
      port: 6379,
      command: nil,
      volume_path: nil,
      host_path: nil,
      affinity_server_names: nil
    })

    docs = parse_yaml_docs(yaml)
    secret = docs[0]
    deployment = docs[1]

    assert_includes secret["stringData"].keys, "REDIS_PASSWORD"

    container = deployment.dig("spec", "template", "spec", "containers", 0)
    env = container["env"].find { |e| e["name"] == "REDIS_PASSWORD" }
    assert_equal "redis-secret", env.dig("valueFrom", "secretKeyRef", "name")
  end

  def test_service_deployment_with_volume_path_and_host_path
    yaml = Nvoi::K8s::Renderer.render_template("service-deployment.yaml", {
      name: "redis",
      image: "redis:7",
      env_vars: {},
      env_keys: [],
      port: 6379,
      command: nil,
      volume_path: "/data",
      host_path: "/mnt/redis-data",
      affinity_server_names: nil
    })

    docs = parse_yaml_docs(yaml)
    deployment = docs[1]

    container = deployment.dig("spec", "template", "spec", "containers", 0)
    assert_equal "/data", container["volumeMounts"][0]["mountPath"]

    volumes = deployment.dig("spec", "template", "spec", "volumes")
    assert_equal "/mnt/redis-data", volumes[0].dig("hostPath", "path")
  end

  def test_service_deployment_with_volume_path_no_host_path
    yaml = Nvoi::K8s::Renderer.render_template("service-deployment.yaml", {
      name: "redis",
      image: "redis:7",
      env_vars: {},
      env_keys: [],
      port: 6379,
      command: nil,
      volume_path: "/data",
      host_path: nil,
      affinity_server_names: nil
    })

    docs = parse_yaml_docs(yaml)
    deployment = docs[1]

    container = deployment.dig("spec", "template", "spec", "containers", 0)
    assert_equal "/data", container["volumeMounts"][0]["mountPath"]

    volumes = deployment.dig("spec", "template", "spec", "volumes")
    refute_nil volumes[0]["emptyDir"]
  end

  def test_service_deployment_with_affinity
    yaml = Nvoi::K8s::Renderer.render_template("service-deployment.yaml", {
      name: "redis",
      image: "redis:7",
      env_vars: {},
      env_keys: [],
      port: 6379,
      command: nil,
      volume_path: nil,
      host_path: nil,
      affinity_server_names: ["master", "workers"]
    })

    docs = parse_yaml_docs(yaml)
    deployment = docs[1]

    affinity = deployment.dig("spec", "template", "spec", "affinity")
    refute_nil affinity

    values = affinity.dig("nodeAffinity", "requiredDuringSchedulingIgnoredDuringExecution", "nodeSelectorTerms", 0, "matchExpressions", 0, "values")
    assert_includes values, "master"
    assert_includes values, "workers"
  end

  def test_service_deployment_full_featured
    yaml = Nvoi::K8s::Renderer.render_template("service-deployment.yaml", {
      name: "elasticsearch",
      image: "elasticsearch:8.11",
      env_vars: {
        "discovery.type" => "single-node",
        "ES_JAVA_OPTS" => "-Xms512m -Xmx512m",
        "xpack.security.enabled" => "false"
      },
      env_keys: ["discovery.type", "ES_JAVA_OPTS", "xpack.security.enabled"],
      port: 9200,
      command: nil,
      volume_path: "/usr/share/elasticsearch/data",
      host_path: "/mnt/es-data",
      affinity_server_names: ["workers"]
    })

    docs = parse_yaml_docs(yaml)

    # All 3 documents present: secret, deployment, service
    assert_equal 3, docs.length
    assert_equal "Secret", docs[0]["kind"]
    assert_equal "Deployment", docs[1]["kind"]
    assert_equal "Service", docs[2]["kind"]
  end
end

class Nvoi::K8s::RendererWorkerDeploymentTest < Minitest::Test
  # ============================================================================
  # WORKER DEPLOYMENT TEMPLATE - ALL POSSIBILITIES
  # ============================================================================

  def test_worker_deployment_basic
    yaml = Nvoi::K8s::Renderer.render_template("worker-deployment.yaml", {
      name: "myapp-worker",
      replicas: 1,
      image: "registry:5000/myapp:latest",
      command: ["bundle", "exec", "sidekiq"],
      secret_name: "app-secret-myapp",
      env_keys: ["DATABASE_URL", "REDIS_URL"],
      resources: { request_memory: "256Mi", request_cpu: "100m", limit_memory: "512Mi", limit_cpu: "500m" },
      affinity_server_names: nil
    })

    assert valid_yaml?(yaml)
    doc = YAML.safe_load(yaml)

    assert_equal "apps/v1", doc["apiVersion"]
    assert_equal "Deployment", doc["kind"]
    assert_equal "myapp-worker", doc["metadata"]["name"]
    assert_equal 1, doc["spec"]["replicas"]

    container = doc.dig("spec", "template", "spec", "containers", 0)
    assert_equal "worker", container["name"]
    assert_equal ["bundle", "exec", "sidekiq"], container["command"]
    assert_equal 2, container["env"].length

    resources = container["resources"]
    assert_equal "256Mi", resources.dig("requests", "memory")
    assert_equal "100m", resources.dig("requests", "cpu")
    assert_equal "512Mi", resources.dig("limits", "memory")
    assert_equal "500m", resources.dig("limits", "cpu")
  end

  def test_worker_deployment_with_affinity
    yaml = Nvoi::K8s::Renderer.render_template("worker-deployment.yaml", {
      name: "myapp-worker",
      replicas: 3,
      image: "registry:5000/myapp:latest",
      command: ["bundle", "exec", "sidekiq", "-c", "10"],
      secret_name: "app-secret-myapp",
      env_keys: ["DATABASE_URL", "REDIS_URL"],
      resources: { request_memory: "512Mi", request_cpu: "250m", limit_memory: "1Gi", limit_cpu: "1000m" },
      affinity_server_names: ["workers"]
    })

    assert valid_yaml?(yaml)
    doc = YAML.safe_load(yaml)

    assert_equal 3, doc["spec"]["replicas"]

    affinity = doc.dig("spec", "template", "spec", "affinity")
    refute_nil affinity

    values = affinity.dig("nodeAffinity", "requiredDuringSchedulingIgnoredDuringExecution", "nodeSelectorTerms", 0, "matchExpressions", 0, "values")
    assert_includes values, "workers"
  end

  def test_worker_deployment_complex_command
    yaml = Nvoi::K8s::Renderer.render_template("worker-deployment.yaml", {
      name: "myapp-scheduler",
      replicas: 1,
      image: "registry:5000/myapp:latest",
      command: ["/bin/sh", "-c", "bundle exec clockwork config/clock.rb"],
      secret_name: "app-secret-myapp",
      env_keys: ["DATABASE_URL"],
      resources: { request_memory: "128Mi", request_cpu: "50m", limit_memory: "256Mi", limit_cpu: "100m" },
      affinity_server_names: nil
    })

    assert valid_yaml?(yaml)
    doc = YAML.safe_load(yaml)

    container = doc.dig("spec", "template", "spec", "containers", 0)
    assert_equal 3, container["command"].length
    assert_equal "/bin/sh", container["command"][0]
  end

  def test_worker_deployment_many_env_vars
    yaml = Nvoi::K8s::Renderer.render_template("worker-deployment.yaml", {
      name: "myapp-worker",
      replicas: 2,
      image: "registry:5000/myapp:latest",
      command: ["bundle", "exec", "sidekiq"],
      secret_name: "app-secret-myapp",
      env_keys: ["DATABASE_URL", "REDIS_URL", "AWS_ACCESS_KEY", "AWS_SECRET_KEY", "S3_BUCKET", "SMTP_HOST"],
      resources: { request_memory: "256Mi", request_cpu: "100m", limit_memory: "512Mi", limit_cpu: "500m" },
      affinity_server_names: nil
    })

    assert valid_yaml?(yaml)
    doc = YAML.safe_load(yaml)

    container = doc.dig("spec", "template", "spec", "containers", 0)
    assert_equal 6, container["env"].length

    env_names = container["env"].map { |e| e["name"] }
    assert_includes env_names, "DATABASE_URL"
    assert_includes env_names, "S3_BUCKET"
  end
end
