# frozen_string_literal: true

require "test_helper"

class TestComputeProviderActions < Minitest::Test
  def setup
    @base_config = { "application" => { "name" => "test" } }
  end

  # SetComputeProvider

  def test_set_hetzner_provider
    result = Nvoi::ConfigApi.set_compute_provider(
      @base_config,
      provider: "hetzner",
      api_token: "token123",
      server_type: "cx22",
      server_location: "fsn1"
    )

    assert result.success?

    assert_equal "token123", result.data["application"]["compute_provider"]["hetzner"]["api_token"]
    assert_equal "cx22", result.data["application"]["compute_provider"]["hetzner"]["server_type"]
    assert_equal "fsn1", result.data["application"]["compute_provider"]["hetzner"]["server_location"]
    assert_nil result.data["application"]["compute_provider"]["aws"]
    assert_nil result.data["application"]["compute_provider"]["scaleway"]
  end

  def test_set_aws_provider
    result = Nvoi::ConfigApi.set_compute_provider(
      @base_config,
      provider: "aws",
      access_key_id: "AKIA...",
      secret_access_key: "secret",
      region: "us-east-1",
      instance_type: "t3.micro"
    )

    assert result.success?

    assert_equal "AKIA...", result.data["application"]["compute_provider"]["aws"]["access_key_id"]
    assert_equal "secret", result.data["application"]["compute_provider"]["aws"]["secret_access_key"]
    assert_equal "us-east-1", result.data["application"]["compute_provider"]["aws"]["region"]
    assert_equal "t3.micro", result.data["application"]["compute_provider"]["aws"]["instance_type"]
  end

  def test_set_scaleway_provider
    result = Nvoi::ConfigApi.set_compute_provider(
      @base_config,
      provider: "scaleway",
      secret_key: "scw-key",
      project_id: "proj-123",
      zone: "fr-par-1",
      server_type: "DEV1-S"
    )

    assert result.success?

    assert_equal "scw-key", result.data["application"]["compute_provider"]["scaleway"]["secret_key"]
    assert_equal "proj-123", result.data["application"]["compute_provider"]["scaleway"]["project_id"]
  end

  def test_set_replaces_existing_provider
    config_with_hetzner = {
      "application" => {
        "name" => "test",
        "compute_provider" => { "hetzner" => { "api_token" => "old" } }
      }
    }

    result = Nvoi::ConfigApi.set_compute_provider(
      config_with_hetzner,
      provider: "aws",
      access_key_id: "new",
      secret_access_key: "secret",
      region: "us-west-2",
      instance_type: "t3.small"
    )

    assert result.success?

    assert_nil result.data["application"]["compute_provider"]["hetzner"]
    assert_equal "new", result.data["application"]["compute_provider"]["aws"]["access_key_id"]
  end

  def test_set_fails_without_provider
    result = Nvoi::ConfigApi.set_compute_provider(@base_config)

    assert result.failure?
    assert_equal :invalid_args, result.error_type
    assert_match(/provider/, result.error_message)
  end

  def test_set_fails_with_invalid_provider
    result = Nvoi::ConfigApi.set_compute_provider(
      @base_config,
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

    result = Nvoi::ConfigApi.delete_compute_provider(config_with_provider)

    assert result.success?
    assert_equal({}, result.data["application"]["compute_provider"])
  end
end
