# frozen_string_literal: true

require "test_helper"

class TestDomainProviderActions < Minitest::Test
  def setup
    @base_config = { "application" => { "name" => "test" } }
  end

  # SetDomainProvider

  def test_set_cloudflare_provider
    result = Nvoi::ConfigApi.set_domain_provider(
      @base_config,
      provider: "cloudflare",
      api_token: "cf_token_123",
      account_id: "acc_456"
    )

    assert result.success?

    assert_equal "cf_token_123", result.data["application"]["domain_provider"]["cloudflare"]["api_token"]
    assert_equal "acc_456", result.data["application"]["domain_provider"]["cloudflare"]["account_id"]
  end

  def test_set_replaces_existing_provider
    config_with_cf = {
      "application" => {
        "name" => "test",
        "domain_provider" => { "cloudflare" => { "api_token" => "old" } }
      }
    }

    result = Nvoi::ConfigApi.set_domain_provider(
      config_with_cf,
      provider: "cloudflare",
      api_token: "new_token",
      account_id: "new_acc"
    )

    assert result.success?
    assert_equal "new_token", result.data["application"]["domain_provider"]["cloudflare"]["api_token"]
  end

  def test_set_fails_without_provider
    result = Nvoi::ConfigApi.set_domain_provider(@base_config)

    assert result.failure?
    assert_equal :invalid_args, result.error_type
    assert_match(/provider/, result.error_message)
  end

  def test_set_fails_with_invalid_provider
    result = Nvoi::ConfigApi.set_domain_provider(
      @base_config,
      provider: "route53"
    )

    assert result.failure?
    assert_equal :invalid_args, result.error_type
    assert_match(/must be one of/, result.error_message)
  end

  # DeleteDomainProvider

  def test_delete_clears_provider
    config_with_provider = {
      "application" => {
        "name" => "test",
        "domain_provider" => { "cloudflare" => { "api_token" => "tok" } }
      }
    }

    result = Nvoi::ConfigApi.delete_domain_provider(config_with_provider)

    assert result.success?
    assert_equal({}, result.data["application"]["domain_provider"])
  end
end
