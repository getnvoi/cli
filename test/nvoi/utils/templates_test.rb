# frozen_string_literal: true

require "test_helper"

class TemplatesTest < Minitest::Test
  def test_template_binding_creates_accessors
    binding = Nvoi::Utils::TemplateBinding.new(name: "myapp", port: 3000)

    assert_equal "myapp", binding.name
    assert_equal 3000, binding.port
  end

  def test_template_binding_get_binding
    binding_obj = Nvoi::Utils::TemplateBinding.new(message: "hello")
    b = binding_obj.get_binding

    assert_kind_of Binding, b
  end

  def test_template_binding_with_hash_values
    data = {
      env: { "RAILS_ENV" => "production" },
      mounts: { "/data" => "volume1" }
    }
    binding = Nvoi::Utils::TemplateBinding.new(data)

    assert_equal({ "RAILS_ENV" => "production" }, binding.env)
    assert_equal({ "/data" => "volume1" }, binding.mounts)
  end
end
