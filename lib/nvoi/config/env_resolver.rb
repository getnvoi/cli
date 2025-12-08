# frozen_string_literal: true

module Nvoi
  module Config
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

        env["DATABASE_ADAPTER"] = db.adapter if db.adapter && !db.adapter.empty?

        # Handle database URL
        if db.adapter == "sqlite3"
          env["DATABASE_URL"] = "sqlite://data/db/production.sqlite3"
        elsif db.url && !db.url.empty?
          env["DATABASE_URL"] = db.url
        end

        # Inject database secrets
        db.secrets&.each do |key, value|
          env[key] = value
        end
      end
    end
  end
end
