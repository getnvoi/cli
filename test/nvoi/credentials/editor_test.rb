# frozen_string_literal: true

require "test_helper"

class Nvoi::Credentials::EditorTest < Minitest::Test
  def test_validate_content_accepts_scaleway_compute_provider
    content = <<~YAML
      application:
        name: test-app
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

    editor = build_editor
    error = editor.send(:validate, content)

    assert_nil error, "Expected no error for scaleway config, got: #{error}"
  end

  def test_validate_content_accepts_hetzner_compute_provider
    content = <<~YAML
      application:
        name: test-app
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

    editor = build_editor
    error = editor.send(:validate, content)

    assert_nil error, "Expected no error for hetzner config, got: #{error}"
  end

  def test_validate_content_rejects_missing_compute_provider
    content = <<~YAML
      application:
        name: test-app
        environment: production
        domain_provider:
          cloudflare:
            api_token: "test-token"
            account_id: "test-account"
        servers:
          master:
            type: cx22
    YAML

    editor = build_editor
    error = editor.send(:validate, content)

    assert_match(/compute_provider/, error)
  end

  def test_validate_content_requires_scaleway_secret_key
    content = <<~YAML
      application:
        name: test-app
        environment: production
        domain_provider:
          cloudflare:
            api_token: "test-token"
            account_id: "test-account"
        compute_provider:
          scaleway:
            project_id: "test-project"
            server_type: "DEV1-S"
        servers:
          master:
            type: DEV1-S
    YAML

    editor = build_editor
    error = editor.send(:validate, content)

    assert_match(/secret_key/, error)
  end

  def test_validate_content_requires_scaleway_project_id
    content = <<~YAML
      application:
        name: test-app
        environment: production
        domain_provider:
          cloudflare:
            api_token: "test-token"
            account_id: "test-account"
        compute_provider:
          scaleway:
            secret_key: "test-secret"
            server_type: "DEV1-S"
        servers:
          master:
            type: DEV1-S
    YAML

    editor = build_editor
    error = editor.send(:validate, content)

    assert_match(/project_id/, error)
  end

  def test_validate_content_requires_scaleway_server_type
    content = <<~YAML
      application:
        name: test-app
        environment: production
        domain_provider:
          cloudflare:
            api_token: "test-token"
            account_id: "test-account"
        compute_provider:
          scaleway:
            secret_key: "test-secret"
            project_id: "test-project"
        servers:
          master:
            type: DEV1-S
    YAML

    editor = build_editor
    error = editor.send(:validate, content)

    assert_match(/server_type/, error)
  end

  private

    def build_editor
      manager = Minitest::Mock.new
      Nvoi::Credentials::Editor.new(manager)
    end
end
