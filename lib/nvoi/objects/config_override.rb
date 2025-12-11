# frozen_string_literal: true

module Nvoi
  module Objects
    # ConfigOverride allows CLI to override app name and subdomain for branch deployments
    class ConfigOverride
      BRANCH_PATTERN = /\A[a-z0-9-]+\z/

      attr_reader :branch

      def initialize(branch:)
        validate!(branch)
        @branch = branch
      end

      # Apply overrides to config
      def apply(config)
        # Prefix branch to application name
        config.deploy.application.name = "#{config.deploy.application.name}-#{@branch}"

        # Prefix branch to all service subdomains
        config.deploy.application.app.each_value do |svc|
          svc.subdomain = "#{@branch}-#{svc.subdomain}"
        end

        config
      end

      private

        def validate!(branch)
          raise ArgumentError, "--branch value required" unless branch && !branch.empty?
          raise ArgumentError, "invalid branch format (lowercase alphanumeric and hyphens only)" unless branch.match?(BRANCH_PATTERN)
        end
    end
  end
end
