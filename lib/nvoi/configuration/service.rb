# frozen_string_literal: true

module Nvoi
  module Configuration
    # Service defines a generic service
    class Service
      attr_accessor :servers, :image, :port, :command, :env, :mount

      def initialize(data = {})
        @servers = data["servers"] || []
        @image = data["image"]
        @port = data["port"]&.to_i
        @command = data["command"]
        @env = data["env"] || {}
        @mount = data["mount"] || {}
      end

      def to_service_spec(app_name, service_name)
        cmd = @command ? @command.split : []
        port = @port && @port.positive? ? @port : infer_port_from_image

        Objects::ServiceSpec.new(
          name: "#{app_name}-#{service_name}",
          image: @image,
          port:,
          command: cmd,
          env: @env,
          mounts: @mount,
          replicas: 1,
          stateful_set: false,
          servers: @servers
        )
      end

      private

        def infer_port_from_image
          case @image
          when /redis/ then 6379
          when /postgres/ then 5432
          when /mysql/ then 3306
          when /memcache/ then 11211
          when /mongo/ then 27017
          when /elastic/ then 9200
          else 0
          end
        end
    end

    # SshKey defines SSH key content (stored in encrypted config)
    class SshKey
      attr_accessor :private_key, :public_key

      def initialize(data = {})
        @private_key = data["private_key"]
        @public_key = data["public_key"]
      end
    end
  end
end
