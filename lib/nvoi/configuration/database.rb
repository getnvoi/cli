# frozen_string_literal: true

module Nvoi
  module Configuration
    # Database defines database configuration
    class Database
      attr_accessor :servers, :adapter, :url, :image, :mount, :secrets, :path

      def initialize(data = nil)
        data ||= {}
        @servers = data["servers"] || []
        @adapter = data["adapter"]
        @url = data["url"]
        @image = data["image"]
        @mount = data["mount"] || {}
        @secrets = data["secrets"] || {}
        @path = data["path"]
      end

      def postgres?
        @adapter&.downcase&.start_with?("postgres")
      end

      def mysql?
        @adapter&.downcase == "mysql"
      end

      def sqlite?
        @adapter&.downcase&.start_with?("sqlite")
      end

      def to_service_spec(namer)
        return nil if @adapter&.downcase&.start_with?("sqlite")

        port = case @adapter&.downcase
        when "mysql" then 3306
        else 5432
        end

        image = @image || Utils::Constants::DATABASE_IMAGES[@adapter&.downcase]

        Configuration::Deployment.new(
          name: namer.database_service_name,
          image:,
          port:,
          env: nil,
          mounts: @mount,
          replicas: 1,
          stateful_set: true,
          secrets: @secrets,
          servers: @servers
        )
      end
    end
  end
end
