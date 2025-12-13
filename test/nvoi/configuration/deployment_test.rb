# frozen_string_literal: true

require "test_helper"

class DeploymentTest < Minitest::Test
  def test_deployment_minimal
    spec = Nvoi::Configuration::Deployment.new(
      name: "myapp-web",
      image: "myapp:latest"
    )

    assert_equal "myapp-web", spec.name
    assert_equal "myapp:latest", spec.image
    assert_equal 0, spec.port
    assert_equal [], spec.command
    assert_equal({}, spec.env)
    assert_equal({}, spec.mounts)
    assert_equal 1, spec.replicas
    assert_nil spec.healthcheck
    assert_equal false, spec.stateful_set
    assert_equal({}, spec.secrets)
    assert_equal [], spec.servers
  end

  def test_deployment_full
    spec = Nvoi::Configuration::Deployment.new(
      name: "myapp-web",
      image: "myapp:latest",
      port: 3000,
      command: ["bundle", "exec", "puma"],
      env: { "RAILS_ENV" => "production" },
      mounts: { "/data" => "myapp-data" },
      replicas: 2,
      healthcheck: { path: "/health" },
      stateful_set: true,
      secrets: { "DATABASE_URL" => "postgres://..." },
      servers: ["master", "workers"]
    )

    assert_equal "myapp-web", spec.name
    assert_equal "myapp:latest", spec.image
    assert_equal 3000, spec.port
    assert_equal ["bundle", "exec", "puma"], spec.command
    assert_equal({ "RAILS_ENV" => "production" }, spec.env)
    assert_equal({ "/data" => "myapp-data" }, spec.mounts)
    assert_equal 2, spec.replicas
    assert_equal({ path: "/health" }, spec.healthcheck)
    assert_equal true, spec.stateful_set
    assert_equal({ "DATABASE_URL" => "postgres://..." }, spec.secrets)
    assert_equal ["master", "workers"], spec.servers
  end

  def test_deployment_nil_defaults
    spec = Nvoi::Configuration::Deployment.new(
      name: "myapp-web",
      image: "myapp:latest",
      command: nil,
      env: nil,
      mounts: nil,
      secrets: nil,
      servers: nil
    )

    assert_equal [], spec.command
    assert_equal({}, spec.env)
    assert_equal({}, spec.mounts)
    assert_equal({}, spec.secrets)
    assert_equal [], spec.servers
  end
end
