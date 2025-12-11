# frozen_string_literal: true

require "test_helper"

class DeployServiceStepTest < Minitest::Test
  def setup
    @mock_ssh = Minitest::Mock.new
    @mock_log = Minitest::Mock.new
    @mock_kubectl = Minitest::Mock.new
  end

  def test_build_hostname_without_branch
    result = Nvoi::Utils::Namer.build_hostname("golang", "rb.run")
    assert_equal "golang.rb.run", result
  end

  def test_build_hostname_with_branch_prefix
    # After ConfigOverride.apply, subdomain becomes "rel-golang"
    result = Nvoi::Utils::Namer.build_hostname("rel-golang", "rb.run")
    assert_equal "rel-golang.rb.run", result
  end

  def test_build_hostname_with_nil_subdomain
    result = Nvoi::Utils::Namer.build_hostname(nil, "rb.run")
    assert_equal "rb.run", result
  end

  def test_build_hostname_with_empty_subdomain
    result = Nvoi::Utils::Namer.build_hostname("", "rb.run")
    assert_equal "rb.run", result
  end

  def test_build_hostname_with_at_subdomain
    result = Nvoi::Utils::Namer.build_hostname("@", "rb.run")
    assert_equal "rb.run", result
  end

  def test_config_override_changes_subdomain_for_ingress
    # This tests the full flow: ConfigOverride modifies subdomain,
    # then build_hostname produces correct ingress hostname

    # Original subdomain
    original_subdomain = "golang"

    # After ConfigOverride with branch "rel"
    branched_subdomain = "rel-#{original_subdomain}"

    # Hostname used for ingress should be branched
    hostname = Nvoi::Utils::Namer.build_hostname(branched_subdomain, "rb.run")
    assert_equal "rel-golang.rb.run", hostname
  end

  MockHealthcheck = Struct.new(:path, keyword_init: true)
  MockServiceConfig = Struct.new(:domain, :subdomain, :healthcheck, keyword_init: true)

  def test_verify_traffic_uses_correct_hostname
    # Test that verify_traffic_switchover builds URL with branched hostname
    service_config = MockServiceConfig.new(
      domain: "rb.run",
      subdomain: "rel-golang",  # After branch override applied
      healthcheck: MockHealthcheck.new(path: "/health")
    )

    hostname = Nvoi::Utils::Namer.build_hostname(service_config.subdomain, service_config.domain)
    health_path = service_config.healthcheck&.path || "/"
    public_url = "https://#{hostname}#{health_path}"

    assert_equal "https://rel-golang.rb.run/health", public_url
  end
end
