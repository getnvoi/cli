# frozen_string_literal: true

module Nvoi
  module Objects
    # ServiceSpec is the CORE primitive - pure K8s deployment specification
    class ServiceSpec
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
