# frozen_string_literal: true

require "test_helper"

class TestComputeProviderActions < Minitest::Test
  def setup
    @master_key = Nvoi::Utils::Crypto.generate_key
    @base_config = { "application" => { "name" => "test" } }
    @encrypted = encrypt(@base_config)
  end

  # SetComputeProvider

  def test_set_hetzner_provider
    result = Nvoi::ConfigApi.set_compute_provider(
      @encrypted, @master_key,
      provider: "hetzner",
      api_token: "token123",
      server_type: "cx22",
      server_location: "fsn1"
    )

    assert result.success?
    data = decrypt(result.config)

    assert_equal "token123", data["application"]["compute_provider"]["hetzner"]["api_token"]
    assert_equal "cx22", data["application"]["compute_provider"]["hetzner"]["server_type"]
    assert_equal "fsn1", data["application"]["compute_provider"]["hetzner"]["server_location"]
    assert_nil data["application"]["compute_provider"]["aws"]
    assert_nil data["application"]["compute_provider"]["scaleway"]
  end

  def test_set_aws_provider
    result = Nvoi::ConfigApi.set_compute_provider(
      @encrypted, @master_key,
      provider: "aws",
      access_key_id: "AKIA...",
      secret_access_key: "secret",
      region: "us-east-1",
      instance_type: "t3.micro"
    )

    assert result.success?
    data = decrypt(result.config)

    assert_equal "AKIA...", data["application"]["compute_provider"]["aws"]["access_key_id"]
    assert_equal "secret", data["application"]["compute_provider"]["aws"]["secret_access_key"]
    assert_equal "us-east-1", data["application"]["compute_provider"]["aws"]["region"]
    assert_equal "t3.micro", data["application"]["compute_provider"]["aws"]["instance_type"]
  end

  def test_set_scaleway_provider
    result = Nvoi::ConfigApi.set_compute_provider(
      @encrypted, @master_key,
      provider: "scaleway",
      secret_key: "scw-key",
      project_id: "proj-123",
      zone: "fr-par-1",
      server_type: "DEV1-S"
    )

    assert result.success?
    data = decrypt(result.config)

    assert_equal "scw-key", data["application"]["compute_provider"]["scaleway"]["secret_key"]
    assert_equal "proj-123", data["application"]["compute_provider"]["scaleway"]["project_id"]
  end

  def test_set_replaces_existing_provider
    config_with_hetzner = {
      "application" => {
        "name" => "test",
        "compute_provider" => { "hetzner" => { "api_token" => "old" } }
      }
    }
    encrypted = encrypt(config_with_hetzner)

    result = Nvoi::ConfigApi.set_compute_provider(
      encrypted, @master_key,
      provider: "aws",
      access_key_id: "new",
      secret_access_key: "secret",
      region: "us-west-2",
      instance_type: "t3.small"
    )

    assert result.success?
    data = decrypt(result.config)

    assert_nil data["application"]["compute_provider"]["hetzner"]
    assert_equal "new", data["application"]["compute_provider"]["aws"]["access_key_id"]
  end

  def test_set_fails_without_provider
    result = Nvoi::ConfigApi.set_compute_provider(@encrypted, @master_key)

    assert result.failure?
    assert_equal :invalid_args, result.error_type
    assert_match(/provider is required/, result.error_message)
  end

  def test_set_fails_with_invalid_provider
    result = Nvoi::ConfigApi.set_compute_provider(
      @encrypted, @master_key,
      provider: "digitalocean"
    )

    assert result.failure?
    assert_equal :invalid_args, result.error_type
    assert_match(/must be one of/, result.error_message)
  end

  # DeleteComputeProvider

  def test_delete_clears_all_providers
    config_with_provider = {
      "application" => {
        "name" => "test",
        "compute_provider" => { "hetzner" => { "api_token" => "tok" } }
      }
    }
    encrypted = encrypt(config_with_provider)

    result = Nvoi::ConfigApi.delete_compute_provider(encrypted, @master_key)

    assert result.success?
    data = decrypt(result.config)

    assert_equal({}, data["application"]["compute_provider"])
  end

  private

  def encrypt(data)
    Nvoi::Utils::Crypto.encrypt(YAML.dump(data), @master_key)
  end

  def decrypt(encrypted)
    YAML.safe_load(Nvoi::Utils::Crypto.decrypt(encrypted, @master_key))
  end
end
