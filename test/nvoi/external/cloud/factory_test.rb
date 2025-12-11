# frozen_string_literal: true

require "test_helper"

class CloudFactoryTest < Minitest::Test
  # Mock config classes
  MockHetznerConfig = Struct.new(:api_token, :server_type, :server_location, keyword_init: true)
  MockAWSConfig = Struct.new(:access_key_id, :secret_access_key, :region, :instance_type, keyword_init: true)
  MockScalewayConfig = Struct.new(:secret_key, :project_id, :zone, :server_type, keyword_init: true)

  MockConfig = Struct.new(:provider_name, :hetzner, :aws, :scaleway, keyword_init: true)

  def test_for_hetzner
    config = MockConfig.new(
      provider_name: "hetzner",
      hetzner: MockHetznerConfig.new(api_token: "test-token")
    )

    provider = Nvoi::External::Cloud::Factory.for(config)

    assert_kind_of Nvoi::External::Cloud::Hetzner, provider
  end

  def test_for_scaleway
    config = MockConfig.new(
      provider_name: "scaleway",
      scaleway: MockScalewayConfig.new(secret_key: "secret", project_id: "proj-123", zone: "fr-par-1")
    )

    provider = Nvoi::External::Cloud::Factory.for(config)

    assert_kind_of Nvoi::External::Cloud::Scaleway, provider
  end

  def test_for_unknown_provider
    config = MockConfig.new(provider_name: "unknown")

    assert_raises(Nvoi::Errors::ProviderError) do
      Nvoi::External::Cloud::Factory.for(config)
    end
  end
end
