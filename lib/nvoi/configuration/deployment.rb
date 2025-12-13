# frozen_string_literal: true

module Nvoi
  module Configuration
    # Deployment is the normalized service definition ready for deployment
    # Created by Configuration::Database and Configuration::Service
    class Deployment
      attr_accessor :name, :image, :port, :command, :env, :mounts, :replicas,
                    :healthcheck, :stateful_set, :secrets, :servers

      def initialize(name:, image:, port: 0, command: [], env: nil, mounts: nil,
                     replicas: 1, healthcheck: nil, stateful_set: false, secrets: nil, servers: [])
        @name = name
        @image = image
        @port = port
        @command = command || []
        @env = env || {}
        @mounts = mounts || {}
        @replicas = replicas
        @healthcheck = healthcheck
        @stateful_set = stateful_set
        @secrets = secrets || {}
        @servers = servers || []
      end
    end
  end
end
