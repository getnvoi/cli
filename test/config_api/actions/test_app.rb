# frozen_string_literal: true

require "test_helper"

class TestAppActions < Minitest::Test
  def setup
    @config_with_server = { "application" => { "servers" => { "web" => {}, "workers" => {} } } }
  end

  # SetApp

  def test_set_app_minimal
    result = Nvoi::ConfigApi.set_app(@config_with_server, name: "api", servers: ["web"])

    assert result.success?
    assert result.data["application"]["app"].key?("api")
    assert_equal ["web"], result.data["application"]["app"]["api"]["servers"]
  end

  def test_set_app_with_all_options
    result = Nvoi::ConfigApi.set_app(
      @config_with_server,
      name: "api",
      servers: ["web", "workers"],
      domain: "example.com",
      subdomain: "api",
      port: 3000,
      command: "bundle exec puma",
      pre_run_command: "rake db:migrate",
      env: { "LOG_LEVEL" => "info" },
      mounts: { "logs" => "/app/log" }
    )

    assert result.success?

    app = result.data["application"]["app"]["api"]
    assert_equal ["web", "workers"], app["servers"]
    assert_equal "example.com", app["domain"]
    assert_equal "api", app["subdomain"]
    assert_equal 3000, app["port"]
    assert_equal "bundle exec puma", app["command"]
    assert_equal "rake db:migrate", app["pre_run_command"]
    assert_equal({ "LOG_LEVEL" => "info" }, app["env"])
    assert_equal({ "logs" => "/app/log" }, app["mounts"])
  end

  def test_set_app_updates_existing
    config = {
      "application" => {
        "servers" => { "web" => {} },
        "app" => { "api" => { "servers" => ["web"], "port" => 3000 } }
      }
    }

    result = Nvoi::ConfigApi.set_app(config, name: "api", servers: ["web"], port: 4000)

    assert result.success?
    assert_equal 4000, result.data["application"]["app"]["api"]["port"]
  end

  def test_set_app_fails_without_name
    result = Nvoi::ConfigApi.set_app(@config_with_server, servers: ["web"])

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  def test_set_app_fails_without_servers
    result = Nvoi::ConfigApi.set_app(@config_with_server, name: "api")

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  def test_set_app_fails_with_empty_servers
    result = Nvoi::ConfigApi.set_app(@config_with_server, name: "api", servers: [])

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  def test_set_app_fails_if_server_ref_not_found
    result = Nvoi::ConfigApi.set_app(@config_with_server, name: "api", servers: ["nonexistent"])

    assert result.failure?
    assert_equal :validation_error, result.error_type
    assert_match(/server .* not found/, result.error_message)
  end

  # DeleteApp

  def test_delete_app
    config = {
      "application" => {
        "servers" => { "web" => {} },
        "app" => { "api" => { "servers" => ["web"] }, "worker" => { "servers" => ["web"] } }
      }
    }

    result = Nvoi::ConfigApi.delete_app(config, name: "api")

    assert result.success?
    refute result.data["application"]["app"].key?("api")
    assert result.data["application"]["app"].key?("worker")
  end

  def test_delete_app_fails_if_not_found
    result = Nvoi::ConfigApi.delete_app(@config_with_server, name: "nonexistent")

    assert result.failure?
    assert_equal :validation_error, result.error_type
    assert_match(/not found/, result.error_message)
  end
end
