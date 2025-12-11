# frozen_string_literal: true

require "test_helper"

class ErrorsTest < Minitest::Test
  def test_base_error
    error = Nvoi::Error.new("something failed", details: { code: 500 })
    assert_equal "something failed", error.message
    assert_equal({ code: 500 }, error.details)
  end

  def test_config_error_hierarchy
    assert Nvoi::ConfigError < Nvoi::Error
    assert Nvoi::ConfigNotFoundError < Nvoi::ConfigError
    assert Nvoi::ConfigValidationError < Nvoi::ConfigError
  end

  def test_credential_error_hierarchy
    assert Nvoi::CredentialError < Nvoi::Error
    assert Nvoi::DecryptionError < Nvoi::CredentialError
    assert Nvoi::EncryptionError < Nvoi::CredentialError
    assert Nvoi::InvalidKeyError < Nvoi::CredentialError
  end

  def test_provider_error_hierarchy
    assert Nvoi::ProviderError < Nvoi::Error
    assert Nvoi::ServerCreationError < Nvoi::ProviderError
    assert Nvoi::NetworkError < Nvoi::ProviderError
    assert Nvoi::VolumeError < Nvoi::ProviderError
  end

  def test_ssh_error_hierarchy
    assert Nvoi::SshError < Nvoi::Error
    assert Nvoi::SshConnectionError < Nvoi::SshError
    assert Nvoi::SshCommandError < Nvoi::SshError
  end

  def test_deployment_error
    error = Nvoi::DeploymentError.new("provision_server", "timeout", retryable: true)
    assert_equal "provision_server: timeout", error.message
    assert_equal "provision_server", error.step
    assert error.retryable?
  end

  def test_deployment_error_not_retryable
    error = Nvoi::DeploymentError.new("validate_config", "invalid yaml", retryable: false)
    refute error.retryable?
  end

  def test_database_error
    error = Nvoi::DatabaseError.new("dump", "connection refused")
    assert_equal "database dump: connection refused", error.message
    assert_equal "dump", error.operation
  end

  def test_cloudflare_error_hierarchy
    assert Nvoi::CloudflareError < Nvoi::Error
    assert Nvoi::TunnelError < Nvoi::CloudflareError
    assert Nvoi::DNSError < Nvoi::CloudflareError
  end
end
