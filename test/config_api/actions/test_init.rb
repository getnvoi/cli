# frozen_string_literal: true

require "test_helper"

class TestInitAction < Minitest::Test
  def test_init_creates_config_and_key
    result = Nvoi::ConfigApi.init(name: "myapp")

    assert result.success?
    assert_instance_of String, result.config
    assert_instance_of String, result.master_key
    assert_instance_of String, result.ssh_public_key

    # Verify master key format (64 hex chars)
    assert_equal 64, result.master_key.length
    assert_match(/\A[0-9a-f]+\z/, result.master_key)

    # Verify SSH public key format
    assert result.ssh_public_key.start_with?("ssh-ed25519 ")
  end

  def test_init_config_can_be_decrypted
    result = Nvoi::ConfigApi.init(name: "myapp")

    yaml = Nvoi::Utils::Crypto.decrypt(result.config, result.master_key)
    data = YAML.safe_load(yaml)

    assert_equal "myapp", data["application"]["name"]
    assert_equal "production", data["application"]["environment"]
    assert data["application"]["ssh_keys"]["private_key"]
    assert data["application"]["ssh_keys"]["public_key"]
  end

  def test_init_with_custom_environment
    result = Nvoi::ConfigApi.init(name: "myapp", environment: "staging")

    yaml = Nvoi::Utils::Crypto.decrypt(result.config, result.master_key)
    data = YAML.safe_load(yaml)

    assert_equal "staging", data["application"]["environment"]
  end

  def test_init_creates_empty_sections
    result = Nvoi::ConfigApi.init(name: "myapp")

    yaml = Nvoi::Utils::Crypto.decrypt(result.config, result.master_key)
    data = YAML.safe_load(yaml)

    assert_equal({}, data["application"]["domain_provider"])
    assert_equal({}, data["application"]["compute_provider"])
    assert_equal({}, data["application"]["servers"])
    assert_equal({}, data["application"]["app"])
    assert_equal({}, data["application"]["services"])
    assert_equal({}, data["application"]["env"])
    assert_equal({}, data["application"]["secrets"])
  end

  def test_init_fails_without_name
    result = Nvoi::ConfigApi.init(name: nil)

    assert result.failure?
    assert_equal :invalid_args, result.error_type
    assert_match(/name is required/, result.error_message)
  end

  def test_init_fails_with_empty_name
    result = Nvoi::ConfigApi.init(name: "")

    assert result.failure?
    assert_equal :invalid_args, result.error_type
  end

  def test_init_generates_unique_keys_each_time
    result1 = Nvoi::ConfigApi.init(name: "app1")
    result2 = Nvoi::ConfigApi.init(name: "app2")

    refute_equal result1.master_key, result2.master_key
    refute_equal result1.ssh_public_key, result2.ssh_public_key
  end

  def test_init_ssh_key_is_valid_for_further_operations
    result = Nvoi::ConfigApi.init(name: "myapp")

    yaml = Nvoi::Utils::Crypto.decrypt(result.config, result.master_key)
    data = YAML.safe_load(yaml)

    private_key = data["application"]["ssh_keys"]["private_key"]
    public_key = data["application"]["ssh_keys"]["public_key"]

    # Private key should be OpenSSH format (ed25519)
    assert private_key.include?("OPENSSH PRIVATE KEY") || private_key.include?("PRIVATE KEY")

    # Public key should match result
    assert_equal public_key, result.ssh_public_key
  end
end
