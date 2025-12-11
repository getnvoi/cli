# frozen_string_literal: true

require "erb"

module Nvoi
  module Utils
    # TemplateBinding provides a clean binding for ERB templates
    class TemplateBinding
      def initialize(data)
        data.each do |key, value|
          instance_variable_set("@#{key}", value)
          define_singleton_method(key) { instance_variable_get("@#{key}") }
        end
      end

      def get_binding
        binding
      end
    end

    # Templates handles K8s manifest template loading and rendering
    module Templates
      class << self
        def template_path(name)
          File.join(Nvoi.templates_path, "#{name}.erb")
        end

        def load_template(name)
          path = template_path(name)
          raise TemplateError, "template #{name} not found at #{path}" unless File.exist?(path)

          ERB.new(File.read(path), trim_mode: "-")
        end

        def template_names
          Dir.glob(File.join(Nvoi.templates_path, "*.erb")).map do |path|
            File.basename(path, ".erb")
          end
        end

        # Render a template with the provided data
        def render(name, data)
          template = load_template(name)
          binding_obj = TemplateBinding.new(data)
          template.result(binding_obj.get_binding)
        end
      end
    end
  end
end
