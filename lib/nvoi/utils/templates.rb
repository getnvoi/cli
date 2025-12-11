# frozen_string_literal: true

require "erb"

module Nvoi
  module Utils
    # Templates handles K8s manifest template loading and rendering
    module Templates
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

      class << self
        def template_path(name)
          File.join(Nvoi.templates_path, "#{name}.erb")
        end

        def load_template(name)
          path = template_path(name)
          raise Errors::TemplateError, "template #{name} not found at #{path}" unless File.exist?(path)

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

        # Render a template and apply it via kubectl
        def apply_manifest(ssh, template_name, data)
          manifest = render(template_name, data)
          cmd = "cat <<'EOF' | kubectl apply -f -\n#{manifest}\nEOF"
          ssh.execute(cmd)
        end

        # Wait for a deployment to be ready
        def wait_for_deployment(ssh, name, namespace: "default", timeout: 300)
          ssh.execute("kubectl rollout status deployment/#{name} -n #{namespace} --timeout=#{timeout}s")
        end
      end
    end
  end
end
