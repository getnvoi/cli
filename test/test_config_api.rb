# frozen_string_literal: true

require "test_helper"

class TestConfigApiPublicAPI < Minitest::Test
  def setup
    @base_config = { "application" => { "name" => "test" } }
  end

  # Verify all public methods exist

  def test_responds_to_all_actions
    %i[
      set_compute_provider delete_compute_provider
      set_domain_provider delete_domain_provider
      set_server delete_server
      set_volume delete_volume
      set_app delete_app
      set_database delete_database
      set_secret delete_secret
      set_env delete_env
      set_service delete_service
      init
    ].each do |method|
      assert_respond_to Nvoi::ConfigApi, method
    end
  end

  # Integration test: chained operations

  def test_chained_operations
    # Build up a config through multiple operations
    result = Nvoi::ConfigApi.set_compute_provider(
      @base_config,
      provider: "hetzner",
      api_token: "tok",
      server_type: "cx22",
      server_location: "fsn1"
    )
    assert result.success?

    result = Nvoi::ConfigApi.set_server(result.data, name: "web", master: true)
    assert result.success?

    result = Nvoi::ConfigApi.set_volume(result.data, server: "web", name: "data", size: 50)
    assert result.success?

    result = Nvoi::ConfigApi.set_app(result.data, name: "api", servers: ["web"], port: 3000)
    assert result.success?

    result = Nvoi::ConfigApi.set_env(result.data, key: "RAILS_ENV", value: "production")
    assert result.success?

    result = Nvoi::ConfigApi.set_secret(result.data, key: "SECRET_KEY", value: "abc123")
    assert result.success?

    # Verify final state
    data = result.data

    assert data["application"]["compute_provider"]["hetzner"]
    assert data["application"]["servers"]["web"]
    assert_equal 50, data["application"]["servers"]["web"]["volumes"]["data"]["size"]
    assert data["application"]["app"]["api"]
    assert_equal "production", data["application"]["env"]["RAILS_ENV"]
    assert_equal "abc123", data["application"]["secrets"]["SECRET_KEY"]
  end

  def test_config_api_returns_hash
    result = Nvoi::ConfigApi.set_server(@base_config, name: "web")

    assert result.success?
    assert_instance_of Hash, result.data
  end

  def test_config_api_mutates_in_place
    # Verify that we're mutating the original hash (not creating a new one)
    # This is important for memory efficiency with large configs
    original = { "application" => { "name" => "test" } }

    result = Nvoi::ConfigApi.set_server(original, name: "web")

    assert result.success?
    # The returned data is the same object
    assert_same original, result.data
  end
end
