# frozen_string_literal: true

require "test_helper"

class ErrorsTest < Minitest::Test
  def test_base_error
    error = Nvoi::Errors::Error.new("something failed", details: { code: 500 })
    assert_equal "something failed", error.message
    assert_equal({ code: 500 }, error.details)
  end

  def test_config_error_hierarchy
    assert Nvoi::Errors::ConfigError < Nvoi::Errors::Error
    assert Nvoi::Errors::ConfigNotFoundError < Nvoi::Errors::ConfigError
    assert Nvoi::Errors::ConfigValidationError < Nvoi::Errors::ConfigError
  end

  def test_credential_error_hierarchy
    assert Nvoi::Errors::CredentialError < Nvoi::Errors::Error
    assert Nvoi::Errors::DecryptionError < Nvoi::Errors::CredentialError
    assert Nvoi::Errors::EncryptionError < Nvoi::Errors::CredentialError
    assert Nvoi::Errors::InvalidKeyError < Nvoi::Errors::CredentialError
  end

  def test_provider_error_hierarchy
    assert Nvoi::Errors::ProviderError < Nvoi::Errors::Error
    assert Nvoi::Errors::ServerCreationError < Nvoi::Errors::ProviderError
    assert Nvoi::Errors::NetworkError < Nvoi::Errors::ProviderError
    assert Nvoi::Errors::VolumeError < Nvoi::Errors::ProviderError
  end

  def test_ssh_error_hierarchy
    assert Nvoi::Errors::SshError < Nvoi::Errors::Error
    assert Nvoi::Errors::SshConnectionError < Nvoi::Errors::SshError
    assert Nvoi::Errors::SshCommandError < Nvoi::Errors::SshError
  end

  def test_deployment_error
    error = Nvoi::Errors::DeploymentError.new("provision_server", "timeout", retryable: true)
    assert_equal "provision_server: timeout", error.message
    assert_equal "provision_server", error.step
    assert error.retryable?
  end

  def test_deployment_error_not_retryable
    error = Nvoi::Errors::DeploymentError.new("validate_config", "invalid yaml", retryable: false)
    refute error.retryable?
  end

  def test_database_error
    error = Nvoi::Errors::DatabaseError.new("dump", "connection refused")
    assert_equal "database dump: connection refused", error.message
    assert_equal "dump", error.operation
  end

  def test_cloudflare_error_hierarchy
    assert Nvoi::Errors::CloudflareError < Nvoi::Errors::Error
    assert Nvoi::Errors::TunnelError < Nvoi::Errors::CloudflareError
    assert Nvoi::Errors::DnsError < Nvoi::Errors::CloudflareError
  end
end
