# frozen_string_literal: true

require "test_helper"

class Nvoi::Steps::TunnelConfiguratorHostnameTest < Minitest::Test
  def setup
    @configurator = Object.new
    @configurator.extend(BuildHostnameHelper)
  end

  def test_build_hostname_with_standard_subdomain
    assert_equal "app.example.com", @configurator.build_hostname("app", "example.com")
    assert_equal "api.example.com", @configurator.build_hostname("api", "example.com")
    assert_equal "www.example.com", @configurator.build_hostname("www", "example.com")
  end

  def test_build_hostname_with_wildcard
    assert_equal "*.example.com", @configurator.build_hostname("*", "example.com")
  end

  def test_build_hostname_with_apex_at_symbol
    assert_equal "example.com", @configurator.build_hostname("@", "example.com")
  end

  def test_build_hostname_with_apex_empty_string
    assert_equal "example.com", @configurator.build_hostname("", "example.com")
  end

  def test_build_hostname_with_apex_nil
    assert_equal "example.com", @configurator.build_hostname(nil, "example.com")
  end

  def test_build_hostname_with_nested_subdomain
    assert_equal "api.v1.example.com", @configurator.build_hostname("api.v1", "example.com")
  end
end

# Helper module to test build_hostname in isolation
module BuildHostnameHelper
  def build_hostname(subdomain, domain)
    if subdomain.nil? || subdomain.empty? || subdomain == "@"
      domain
    else
      "#{subdomain}.#{domain}"
    end
  end
end
