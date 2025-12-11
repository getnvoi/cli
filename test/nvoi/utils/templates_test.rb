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
    assert_raises(Nvoi::TemplateError) do
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
end

class TemplateBindingTest < Minitest::Test
  def test_binding_exposes_data_as_methods
    binding_obj = Nvoi::Utils::TemplateBinding.new({ name: "test", count: 5 })

    assert_equal "test", binding_obj.name
    assert_equal 5, binding_obj.count
  end

  def test_get_binding_returns_binding
    binding_obj = Nvoi::Utils::TemplateBinding.new({ foo: "bar" })

    assert_instance_of Binding, binding_obj.get_binding
  end
end
