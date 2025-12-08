# frozen_string_literal: true

require "erb"

module Nvoi
  module K8s
    # Templates handles K8s manifest template loading
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
      end
    end
  end
end
