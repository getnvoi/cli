# frozen_string_literal: true

module Nvoi
  module Utils
    # EnvResolver handles environment variable resolution and injection
    class EnvResolver
      def initialize(config)
        @config = config
      end

      # Returns environment variables for a specific service
      def env_for_service(service_name)
        env = {
          "DEPLOY_ENV" => @config.deploy.application.environment
        }

        # Database env injection
        inject_database_env(env)

        # Global env vars
        @config.deploy.application.env&.each do |k, v|
          env[k] = v
        end

        # Global secrets
        @config.deploy.application.secrets&.each do |k, v|
          env[k] = v
        end

        # Service-specific env
        service = @config.deploy.application.app[service_name]
        if service
          service.env&.each do |k, v|
            env[k] = v
          end
        end

        env
      end

      private

        def inject_database_env(env)
          db = @config.deploy.application.database
          return unless db

          env["DATABASE_ADAPTER"] = db.adapter unless db.adapter.blank?

          # Handle database URL
          if db.adapter == "sqlite3"
            env["DATABASE_URL"] = sqlite_database_url(db)
          elsif !db.url.blank?
            env["DATABASE_URL"] = db.url
          end

          # Inject database secrets
          db.secrets&.each do |key, value|
            env[key] = value
          end
        end

        def sqlite_database_url(db)
          raise Errors::ConfigError, "sqlite3 requires database.mount to be configured" if db.mount.blank?

          mount_path = db.mount.values.first
          app_name = @config.deploy.application.name
          "sqlite://#{mount_path}/#{app_name}-database.sqlite3"
        end
    end
  end
end
