# frozen_string_literal: true

module Nvoi
  module Configuration
    # AppService defines a service in the app section
    class AppService
      attr_accessor :servers, :domain, :subdomain, :port, :healthcheck,
                    :command, :pre_run_command, :env, :mounts

      def initialize(data = nil)
        data ||= {}
        @servers = data["servers"] || []
        @domain = data["domain"]
        @subdomain = data["subdomain"]
        @port = data["port"]&.to_i
        @healthcheck = data["healthcheck"] ? HealthCheck.new(data["healthcheck"]) : nil
        @command = data["command"]
        @pre_run_command = data["pre_run_command"]
        @env = data["env"] || {}
        @mounts = data["mounts"] || {}
      end

      def web?
        @port && @port.positive?
      end

      def worker?
        !web?
      end

      def fqdn
        return nil if @domain.blank?

        @subdomain.blank? ? @domain : "#{@subdomain}.#{@domain}"
      end

      # HealthCheck defines health check configuration
      class HealthCheck
        attr_accessor :type, :path, :port, :command, :interval, :timeout, :retries

        def initialize(data = nil)
          data ||= {}
          @type = data["type"]
          @path = data["path"]
          @port = data["port"]&.to_i
          @command = data["command"]
          @interval = data["interval"]
          @timeout = data["timeout"]
          @retries = data["retries"]&.to_i
        end
      end
    end
  end
end
