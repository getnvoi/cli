# frozen_string_literal: true

module Nvoi
  module Configuration
    # Application contains application-level configuration
    class Application
      attr_accessor :name, :environment, :domain_provider, :compute_provider,
                    :keep_count, :servers, :app, :database, :services, :env,
                    :secrets, :ssh_keys

      def initialize(data = {})
        @name = data["name"]
        @environment = data["environment"] || "production"
        @domain_provider = Providers::DomainProvider.new(data["domain_provider"] || {})
        @compute_provider = Providers::ComputeProvider.new(data["compute_provider"] || {})
        @keep_count = data["keep_count"]&.to_i
        @servers = (data["servers"] || {}).transform_values { |v| Server.new(v || {}) }
        @app = (data["app"] || {}).transform_values { |v| AppService.new(v || {}) }
        @database = data["database"] ? Database.new(data["database"]) : nil
        @services = (data["services"] || {}).transform_values { |v| Service.new(v || {}) }
        @env = data["env"] || {}
        @secrets = data["secrets"] || {}
        @ssh_keys = data["ssh_keys"] ? SshKey.new(data["ssh_keys"]) : nil
      end

      def app_by_name(name)
        @app[name.to_s]
      end

      def server_by_name(name)
        @servers[name.to_s]
      end

      def web_apps
        @app.select { |_, cfg| cfg.web? }
      end

      def workers
        @app.reject { |_, cfg| cfg.web? }
      end
    end
  end
end
