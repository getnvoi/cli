# frozen_string_literal: true

require "test_helper"

class TemplatesTest < Minitest::Test
  def test_template_names_returns_available_templates
    names = Nvoi::Utils::Templates.template_names

    assert_instance_of Array, names
    assert names.any?, "expected some templates to exist"
  end

  def test_load_template_returns_erb_object
    template = Nvoi::Utils::Templates.load_template("app-secret.yaml")

    assert_instance_of ERB, template
  end

  def test_load_template_raises_for_missing_template
    assert_raises(Nvoi::Errors::TemplateError) do
      Nvoi::Utils::Templates.load_template("nonexistent-template")
    end
  end

  def test_render_produces_output
    # Using a template that exists
    result = Nvoi::Utils::Templates.render("app-secret.yaml", {
      name: "test-secret",
      env_vars: { "KEY" => "value" }
    })

    assert_instance_of String, result
    assert_includes result, "test-secret"
    assert_includes result, "apiVersion"
  end

  def test_apply_manifest_renders_and_executes_kubectl
    mock_ssh = Minitest::Mock.new

    # Expect ssh.execute to be called with heredoc containing rendered manifest
    mock_ssh.expect :execute, "deployment.apps/test created", [String]

    result = Nvoi::Utils::Templates.apply_manifest(mock_ssh, "app-secret.yaml", {
      name: "test-secret",
      env_vars: { "KEY" => "value" }
    })

    mock_ssh.verify
    assert_equal "deployment.apps/test created", result
  end

  def test_apply_manifest_command_format
    captured_cmd = nil
    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:execute) { |cmd| captured_cmd = cmd; "ok" }

    Nvoi::Utils::Templates.apply_manifest(mock_ssh, "app-secret.yaml", {
      name: "test-secret",
      env_vars: { "KEY" => "value" }
    })

    assert_match(/^cat <<'EOF' \| kubectl apply -f -/, captured_cmd)
    assert_match(/EOF$/, captured_cmd)
    assert_includes captured_cmd, "test-secret"
  end

  def test_apply_manifest_raises_for_missing_template
    mock_ssh = Minitest::Mock.new

    assert_raises(Nvoi::Errors::TemplateError) do
      Nvoi::Utils::Templates.apply_manifest(mock_ssh, "nonexistent-template", {})
    end
  end

  def test_wait_for_deployment_executes_rollout_status
    mock_ssh = Minitest::Mock.new
    mock_ssh.expect :execute, "deployment \"myapp\" successfully rolled out",
      ["kubectl rollout status deployment/myapp -n default --timeout=300s"]

    result = Nvoi::Utils::Templates.wait_for_deployment(mock_ssh, "myapp")

    mock_ssh.verify
    assert_includes result, "successfully rolled out"
  end

  def test_wait_for_deployment_with_custom_namespace_and_timeout
    mock_ssh = Minitest::Mock.new
    mock_ssh.expect :execute, "ok",
      ["kubectl rollout status deployment/myapp -n production --timeout=600s"]

    Nvoi::Utils::Templates.wait_for_deployment(mock_ssh, "myapp", namespace: "production", timeout: 600)

    mock_ssh.verify
  end
end

class TemplateBindingTest < Minitest::Test
  def test_binding_exposes_data_as_methods
    binding_obj = Nvoi::Utils::Templates::TemplateBinding.new({ name: "test", count: 5 })

    assert_equal "test", binding_obj.name
    assert_equal 5, binding_obj.count
  end

  def test_get_binding_returns_binding
    binding_obj = Nvoi::Utils::Templates::TemplateBinding.new({ foo: "bar" })

    assert_instance_of Binding, binding_obj.get_binding
  end
end
