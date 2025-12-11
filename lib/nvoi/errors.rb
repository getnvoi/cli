# frozen_string_literal: true

module Nvoi
  # Errors module
  module Errors
    # Base error class for all Nvoi errors
    class Error < StandardError
      attr_reader :details

      def initialize(message, details: nil)
        @details = details
        super(message)
      end
    end

    # Configuration errors
    class ConfigError < Error; end
    class ConfigNotFoundError < ConfigError; end
    class ConfigValidationError < ConfigError; end

    # Credential errors
    class CredentialError < Error; end
    class DecryptionError < CredentialError; end
    class EncryptionError < CredentialError; end
    class InvalidKeyError < CredentialError; end

    # Provider errors
    class ProviderError < Error; end
    class ServerCreationError < ProviderError; end
    class NetworkError < ProviderError; end
    class FirewallError < ProviderError; end
    class VolumeError < ProviderError; end
    class ValidationError < ProviderError; end
    class ApiError < ProviderError; end
    class AuthenticationError < ProviderError; end
    class NotFoundError < ProviderError; end
    class ConflictError < ProviderError; end
    class RateLimitError < ProviderError; end

    # Cloudflare errors
    class CloudflareError < Error; end
    class TunnelError < CloudflareError; end
    class DnsError < CloudflareError; end

    # Ssh errors
    class SshError < Error; end
    class SshConnectionError < SshError; end
    class SshCommandError < SshError; end

    # Timeout errors
    class TimeoutError < Error; end

    # Deployment errors
    class DeploymentError < Error
      attr_reader :step, :retryable

      def initialize(step, message, retryable: false, details: nil)
        @step = step
        @retryable = retryable
        super("#{step}: #{message}", details:)
      end

      def retryable?
        @retryable
      end
    end

    # K8s errors
    class K8sError < Error; end
    class TemplateError < K8sError; end

    # Service errors
    class ServiceError < Error; end

    # Database errors
    class DatabaseError < Error
      attr_reader :operation

      def initialize(operation, message, details: nil)
        @operation = operation
        super("database #{operation}: #{message}", details:)
      end
    end
  end
end
