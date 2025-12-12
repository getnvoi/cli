# frozen_string_literal: true

require "test_helper"

class TestConfigApiPublicAPI < Minitest::Test
  def setup
    @master_key = Nvoi::Utils::Crypto.generate_key
    @base_config = { "application" => { "name" => "test" } }
    @encrypted = encrypt(@base_config)
  end

  # Verify all public methods exist

  def test_responds_to_all_actions
    %i[
      set_compute_provider delete_compute_provider
      set_server delete_server
      set_volume delete_volume
      set_app delete_app
      set_database delete_database
      set_secret delete_secret
      set_env delete_env
    ].each do |method|
      assert_respond_to Nvoi::ConfigApi, method
    end
  end

  # Integration test: chained operations

  def test_chained_operations
    # Build up a config through multiple operations
    result = Nvoi::ConfigApi.set_compute_provider(
      @encrypted, @master_key,
      provider: "hetzner",
      api_token: "tok",
      server_type: "cx22",
      server_location: "fsn1"
    )
    assert result.success?

    result = Nvoi::ConfigApi.set_server(result.config, @master_key, name: "web", master: true)
    assert result.success?

    result = Nvoi::ConfigApi.set_volume(result.config, @master_key, server: "web", name: "data", size: 50)
    assert result.success?

    result = Nvoi::ConfigApi.set_app(result.config, @master_key, name: "api", servers: ["web"], port: 3000)
    assert result.success?

    result = Nvoi::ConfigApi.set_env(result.config, @master_key, key: "RAILS_ENV", value: "production")
    assert result.success?

    result = Nvoi::ConfigApi.set_secret(result.config, @master_key, key: "SECRET_KEY", value: "abc123")
    assert result.success?

    # Verify final state
    data = decrypt(result.config)

    assert data["application"]["compute_provider"]["hetzner"]
    assert data["application"]["servers"]["web"]
    assert_equal 50, data["application"]["servers"]["web"]["volumes"]["data"]["size"]
    assert data["application"]["app"]["api"]
    assert_equal "production", data["application"]["env"]["RAILS_ENV"]
    assert_equal "abc123", data["application"]["secrets"]["SECRET_KEY"]
  end

  def test_wrong_key_fails_all_operations
    wrong_key = Nvoi::Utils::Crypto.generate_key

    %i[
      set_compute_provider set_server set_volume
      set_app set_database set_secret set_env
    ].each do |method|
      result = Nvoi::ConfigApi.send(method, @encrypted, wrong_key, **minimal_args_for(method))
      assert result.failure?, "Expected #{method} to fail with wrong key"
      assert_equal :decryption_error, result.error_type
    end
  end

  def test_delete_operations_with_wrong_key
    wrong_key = Nvoi::Utils::Crypto.generate_key

    %i[
      delete_compute_provider delete_database
    ].each do |method|
      result = Nvoi::ConfigApi.send(method, @encrypted, wrong_key)
      assert result.failure?, "Expected #{method} to fail with wrong key"
      assert_equal :decryption_error, result.error_type
    end
  end

  private

  def encrypt(data)
    Nvoi::Utils::Crypto.encrypt(YAML.dump(data), @master_key)
  end

  def decrypt(encrypted)
    YAML.safe_load(Nvoi::Utils::Crypto.decrypt(encrypted, @master_key))
  end

  def minimal_args_for(method)
    case method
    when :set_compute_provider then { provider: "hetzner" }
    when :set_server then { name: "x" }
    when :set_volume then { server: "x", name: "y" }
    when :set_app then { name: "x", servers: ["y"] }
    when :set_database then { servers: ["x"], adapter: "postgres" }
    when :set_secret, :set_env then { key: "X", value: "Y" }
    else {}
    end
  end
end
