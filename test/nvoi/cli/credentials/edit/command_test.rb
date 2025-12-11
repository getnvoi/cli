# frozen_string_literal: true

require "test_helper"

class Nvoi::Cli::Credentials::Edit::CommandTest < Minitest::Test
  def setup
    @command = Nvoi::Cli::Credentials::Edit::Command.new({})
  end

  # ============================================
  # Validation Tests - Valid Configurations
  # ============================================

  def test_validate_accepts_valid_hetzner_config
    content = valid_hetzner_config
    error = @command.send(:validate, content)
    assert_nil error, "Expected no error for hetzner config, got: #{error}"
  end

  def test_validate_accepts_valid_aws_config
    content = valid_aws_config
    error = @command.send(:validate, content)
    assert_nil error, "Expected no error for aws config, got: #{error}"
  end

  def test_validate_accepts_valid_scaleway_config
    content = valid_scaleway_config
    error = @command.send(:validate, content)
    assert_nil error, "Expected no error for scaleway config, got: #{error}"
  end

  # ============================================
  # Validation Tests - Application Basics
  # ============================================

  def test_validate_rejects_missing_application
    content = "foo: bar"
    error = @command.send(:validate, content)
    assert_match(/application section is required/, error)
  end

  def test_validate_rejects_missing_name
    content = <<~YAML
      application:
        environment: production
    YAML
    error = @command.send(:validate, content)
    assert_match(/application.name is required/, error)
  end

  def test_validate_rejects_missing_environment
    content = <<~YAML
      application:
        name: myapp
    YAML
    error = @command.send(:validate, content)
    assert_match(/application.environment is required/, error)
  end

  # ============================================
  # Validation Tests - Cloudflare
  # ============================================

  def test_validate_rejects_missing_cloudflare
    content = <<~YAML
      application:
        name: myapp
        environment: production
    YAML
    error = @command.send(:validate, content)
    assert_match(/cloudflare is required/, error)
  end

  def test_validate_rejects_missing_cloudflare_api_token
    content = <<~YAML
      application:
        name: myapp
        environment: production
        domain_provider:
          cloudflare:
            account_id: "test-account"
    YAML
    error = @command.send(:validate, content)
    assert_match(/api_token is required/, error)
  end

  def test_validate_rejects_missing_cloudflare_account_id
    content = <<~YAML
      application:
        name: myapp
        environment: production
        domain_provider:
          cloudflare:
            api_token: "test-token"
    YAML
    error = @command.send(:validate, content)
    assert_match(/account_id is required/, error)
  end

  # ============================================
  # Validation Tests - Compute Providers
  # ============================================

  def test_validate_rejects_missing_compute_provider
    content = <<~YAML
      application:
        name: myapp
        environment: production
        domain_provider:
          cloudflare:
            api_token: "test-token"
            account_id: "test-account"
    YAML
    error = @command.send(:validate, content)
    assert_match(/compute_provider.*is required/, error)
  end

  def test_validate_rejects_hetzner_missing_api_token
    content = <<~YAML
      application:
        name: myapp
        environment: production
        domain_provider:
          cloudflare:
            api_token: "test-token"
            account_id: "test-account"
        compute_provider:
          hetzner:
            server_type: "cx22"
            server_location: "fsn1"
    YAML
    error = @command.send(:validate, content)
    assert_match(/hetzner.api_token is required/, error)
  end

  def test_validate_rejects_aws_missing_access_key
    content = <<~YAML
      application:
        name: myapp
        environment: production
        domain_provider:
          cloudflare:
            api_token: "test-token"
            account_id: "test-account"
        compute_provider:
          aws:
            secret_access_key: "secret"
            region: "us-east-1"
            instance_type: "t3.micro"
    YAML
    error = @command.send(:validate, content)
    assert_match(/aws.access_key_id is required/, error)
  end

  def test_validate_rejects_scaleway_missing_secret_key
    content = <<~YAML
      application:
        name: myapp
        environment: production
        domain_provider:
          cloudflare:
            api_token: "test-token"
            account_id: "test-account"
        compute_provider:
          scaleway:
            project_id: "test-project"
            server_type: "DEV1-S"
    YAML
    error = @command.send(:validate, content)
    assert_match(/scaleway.secret_key is required/, error)
  end

  def test_validate_rejects_scaleway_missing_project_id
    content = <<~YAML
      application:
        name: myapp
        environment: production
        domain_provider:
          cloudflare:
            api_token: "test-token"
            account_id: "test-account"
        compute_provider:
          scaleway:
            secret_key: "test-secret"
            server_type: "DEV1-S"
    YAML
    error = @command.send(:validate, content)
    assert_match(/scaleway.project_id is required/, error)
  end

  # ============================================
  # Validation Tests - Servers and Services
  # ============================================

  def test_validate_rejects_services_without_servers
    content = <<~YAML
      application:
        name: myapp
        environment: production
        domain_provider:
          cloudflare:
            api_token: "test-token"
            account_id: "test-account"
        compute_provider:
          hetzner:
            api_token: "test-token"
            server_type: "cx22"
            server_location: "fsn1"
        app:
          web:
            servers: [master]
            port: 3000
        ssh_keys:
          private_key: "key"
          public_key: "key.pub"
    YAML
    error = @command.send(:validate, content)
    assert_match(/servers must be defined/, error)
  end

  def test_validate_rejects_undefined_server_reference
    content = <<~YAML
      application:
        name: myapp
        environment: production
        domain_provider:
          cloudflare:
            api_token: "test-token"
            account_id: "test-account"
        compute_provider:
          hetzner:
            api_token: "test-token"
            server_type: "cx22"
            server_location: "fsn1"
        servers:
          master:
            type: cx22
        app:
          web:
            servers: [nonexistent]
            port: 3000
        ssh_keys:
          private_key: "key"
          public_key: "key.pub"
    YAML
    error = @command.send(:validate, content)
    assert_match(/references undefined server: nonexistent/, error)
  end

  # ============================================
  # Validation Tests - SSH Keys
  # ============================================

  def test_validate_rejects_missing_ssh_keys
    content = base_config_without_ssh_keys
    error = @command.send(:validate, content)
    assert_match(/ssh_keys is required/, error)
  end

  def test_validate_rejects_missing_private_key
    content = <<~YAML
      application:
        name: myapp
        environment: production
        domain_provider:
          cloudflare:
            api_token: "test-token"
            account_id: "test-account"
        compute_provider:
          hetzner:
            api_token: "test-token"
            server_type: "cx22"
            server_location: "fsn1"
        servers:
          master:
            type: cx22
        ssh_keys:
          public_key: "key.pub"
    YAML
    error = @command.send(:validate, content)
    assert_match(/private_key is required/, error)
  end

  # ============================================
  # Validation Tests - Database
  # ============================================

  def test_validate_accepts_database_with_url
    content = valid_hetzner_config_with_database_url
    error = @command.send(:validate, content)
    assert_nil error, "Expected no error for database with URL, got: #{error}"
  end

  def test_validate_accepts_postgres_with_secrets
    content = valid_hetzner_config_with_postgres_secrets
    error = @command.send(:validate, content)
    assert_nil error, "Expected no error for postgres with secrets, got: #{error}"
  end

  def test_validate_rejects_postgres_without_url_or_secrets
    content = <<~YAML
      application:
        name: myapp
        environment: production
        domain_provider:
          cloudflare:
            api_token: "test-token"
            account_id: "test-account"
        compute_provider:
          hetzner:
            api_token: "test-token"
            server_type: "cx22"
            server_location: "fsn1"
        servers:
          master:
            type: cx22
        database:
          servers: [master]
          adapter: postgres
        ssh_keys:
          private_key: "key"
          public_key: "key.pub"
    YAML
    error = @command.send(:validate, content)
    assert_match(/POSTGRES_USER is required/, error)
  end

  def test_validate_accepts_sqlite_without_secrets
    content = <<~YAML
      application:
        name: myapp
        environment: production
        domain_provider:
          cloudflare:
            api_token: "test-token"
            account_id: "test-account"
        compute_provider:
          hetzner:
            api_token: "test-token"
            server_type: "cx22"
            server_location: "fsn1"
        servers:
          master:
            type: cx22
        database:
          servers: [master]
          adapter: sqlite3
        ssh_keys:
          private_key: "key"
          public_key: "key.pub"
    YAML
    error = @command.send(:validate, content)
    assert_nil error, "Expected no error for sqlite, got: #{error}"
  end

  def test_validate_rejects_unsupported_database_adapter
    content = <<~YAML
      application:
        name: myapp
        environment: production
        domain_provider:
          cloudflare:
            api_token: "test-token"
            account_id: "test-account"
        compute_provider:
          hetzner:
            api_token: "test-token"
            server_type: "cx22"
            server_location: "fsn1"
        servers:
          master:
            type: cx22
        database:
          servers: [master]
          adapter: mongodb
        ssh_keys:
          private_key: "key"
          public_key: "key.pub"
    YAML
    error = @command.send(:validate, content)
    assert_match(/unsupported database adapter: mongodb/, error)
  end

  # ============================================
  # Validation Tests - YAML Syntax
  # ============================================

  def test_validate_rejects_invalid_yaml
    content = "foo: [bar"
    error = @command.send(:validate, content)
    assert_match(/invalid YAML syntax/, error)
  end

  def test_validate_rejects_non_hash_root
    content = "- item1\n- item2"
    error = @command.send(:validate, content)
    assert_match(/config must be a hash/, error)
  end

  private

    def valid_hetzner_config
      <<~YAML
      application:
        name: myapp
        environment: production
        domain_provider:
          cloudflare:
            api_token: "test-token"
            account_id: "test-account"
        compute_provider:
          hetzner:
            api_token: "test-token"
            server_type: "cx22"
            server_location: "fsn1"
        servers:
          master:
            type: cx22
            location: fsn1
        ssh_keys:
          private_key: "test-private-key"
          public_key: "test-public-key"
    YAML
    end

    def valid_aws_config
      <<~YAML
      application:
        name: myapp
        environment: production
        domain_provider:
          cloudflare:
            api_token: "test-token"
            account_id: "test-account"
        compute_provider:
          aws:
            access_key_id: "AKIAIOSFODNN7EXAMPLE"
            secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
            region: "us-east-1"
            instance_type: "t3.micro"
        servers:
          master:
            type: t3.micro
            location: us-east-1
        ssh_keys:
          private_key: "test-private-key"
          public_key: "test-public-key"
    YAML
    end

    def valid_scaleway_config
      <<~YAML
      application:
        name: myapp
        environment: production
        domain_provider:
          cloudflare:
            api_token: "test-token"
            account_id: "test-account"
        compute_provider:
          scaleway:
            secret_key: "test-secret"
            project_id: "test-project"
            server_type: "DEV1-S"
        servers:
          master:
            type: DEV1-S
            location: fr-par-1
        ssh_keys:
          private_key: "test-private-key"
          public_key: "test-public-key"
    YAML
    end

    def base_config_without_ssh_keys
      <<~YAML
      application:
        name: myapp
        environment: production
        domain_provider:
          cloudflare:
            api_token: "test-token"
            account_id: "test-account"
        compute_provider:
          hetzner:
            api_token: "test-token"
            server_type: "cx22"
            server_location: "fsn1"
        servers:
          master:
            type: cx22
    YAML
    end

    def valid_hetzner_config_with_database_url
      <<~YAML
      application:
        name: myapp
        environment: production
        domain_provider:
          cloudflare:
            api_token: "test-token"
            account_id: "test-account"
        compute_provider:
          hetzner:
            api_token: "test-token"
            server_type: "cx22"
            server_location: "fsn1"
        servers:
          master:
            type: cx22
        database:
          servers: [master]
          adapter: postgres
          url: "postgres://user:pass@localhost:5432/myapp"
        ssh_keys:
          private_key: "test-private-key"
          public_key: "test-public-key"
    YAML
    end

    def valid_hetzner_config_with_postgres_secrets
      <<~YAML
      application:
        name: myapp
        environment: production
        domain_provider:
          cloudflare:
            api_token: "test-token"
            account_id: "test-account"
        compute_provider:
          hetzner:
            api_token: "test-token"
            server_type: "cx22"
            server_location: "fsn1"
        servers:
          master:
            type: cx22
        database:
          servers: [master]
          adapter: postgres
          secrets:
            POSTGRES_USER: myapp
            POSTGRES_PASSWORD: secret
            POSTGRES_DB: myapp_production
        ssh_keys:
          private_key: "test-private-key"
          public_key: "test-public-key"
    YAML
    end
end
