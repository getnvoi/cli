# frozen_string_literal: true

module Nvoi
  module K8s
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

    # Renderer handles K8s manifest rendering and application
    module Renderer
      class << self
        # Render a template with the provided data
        def render_template(name, data)
          template = Templates.load_template(name)
          binding_obj = TemplateBinding.new(data)
          template.result(binding_obj.get_binding)
        end

        # Render a template and apply it via kubectl
        def apply_manifest(ssh, template_name, data)
          manifest = render_template(template_name, data)

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
