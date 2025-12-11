# frozen_string_literal: true

require "test_helper"

class CloudDelegationTest < Minitest::Test
  # Mock config classes (same as factory_test.rb)
  MockHetznerConfig = Struct.new(:api_token, :server_type, :server_location, keyword_init: true)
  MockScalewayConfig = Struct.new(:secret_key, :project_id, :zone, :server_type, keyword_init: true)
  MockConfig = Struct.new(:provider_name, :hetzner, :aws, :scaleway, keyword_init: true)

  def test_for_delegates_to_factory
    config = MockConfig.new(
      provider_name: "hetzner",
      hetzner: MockHetznerConfig.new(api_token: "test-token")
    )

    # Cloud.for should delegate to Factory.for
    provider = Nvoi::External::Cloud.for(config)

    assert_kind_of Nvoi::External::Cloud::Hetzner, provider
  end

  def test_for_with_scaleway_delegates_to_factory
    config = MockConfig.new(
      provider_name: "scaleway",
      scaleway: MockScalewayConfig.new(secret_key: "secret", project_id: "proj-123", zone: "fr-par-1")
    )

    provider = Nvoi::External::Cloud.for(config)

    assert_kind_of Nvoi::External::Cloud::Scaleway, provider
  end

  def test_for_with_unknown_provider_raises
    config = MockConfig.new(provider_name: "unknown")

    assert_raises(Nvoi::Errors::ProviderError) do
      Nvoi::External::Cloud.for(config)
    end
  end

  def test_validate_delegates_to_factory
    config = MockConfig.new(
      provider_name: "hetzner",
      hetzner: MockHetznerConfig.new(
        api_token: "test-token",
        server_type: "cx11",
        server_location: "nbg1"
      )
    )

    provider = Minitest::Mock.new
    provider.expect :validate_credentials, true
    provider.expect :validate_instance_type, true, ["cx11"]
    provider.expect :validate_region, true, ["nbg1"]

    # Should not raise
    Nvoi::External::Cloud.validate(config, provider)

    provider.verify
  end
end
