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

        # Regenerate resource names with new app name
        regenerate_resource_names(config)

        config
      end

      private

        def validate!(branch)
          raise ArgumentError, "--branch value required" unless branch && !branch.empty?
          raise ArgumentError, "invalid branch format (lowercase alphanumeric and hyphens only)" unless branch.match?(BRANCH_PATTERN)
        end

        def regenerate_resource_names(config)
          namer = Utils::Namer.new(config)
          config.namer = namer
          config.container_prefix = namer.infer_container_prefix
          config.server_name = namer.server_name(find_master_group(config), 1)
          config.firewall_name = namer.firewall_name
          config.network_name = namer.network_name
          config.docker_network_name = namer.docker_network_name
        end

        def find_master_group(config)
          servers = config.deploy.application.servers
          return "master" if servers.empty?

          servers.each { |name, srv_cfg| return name if srv_cfg&.master }
          return servers.keys.first if servers.size == 1

          "master"
        end
    end
  end
end
