# frozen_string_literal: true

require "digest"

module Nvoi
  module Utils
    # Namer handles resource naming and inference
    class Namer
      def initialize(config)
        @config = config
      end

      # Generate a container name prefix
      def infer_container_prefix
        base = infer_base_prefix
        name = @config.deploy.application.name

        prefix = name ? "#{base}-#{name}" : base

        # Truncate to 63 chars (DNS limit) with hash for uniqueness
        if prefix.length > 63
          hash = hash_string(prefix)[0, 8]
          max_len = 63 - hash.length - 1
          prefix = "#{prefix[0, max_len]}-#{hash}"
        end

        prefix
      end

      # ============================================================================
      # INFRASTRUCTURE RESOURCES
      # ============================================================================

      # ServerName returns the server name for a given group and index
      def server_name(group, index)
        "#{@config.deploy.application.name}-#{group}-#{index}"
      end

      def firewall_name
        "#{@config.container_prefix}-firewall"
      end

      def network_name
        "#{@config.container_prefix}-network"
      end

      def docker_network_name
        "#{@config.container_prefix}-docker-network"
      end

      # ============================================================================
      # DATABASE RESOURCES
      # ============================================================================

      def database_service_name
        "db-#{@config.deploy.application.name}"
      end

      def database_stateful_set_name
        "db-#{@config.deploy.application.name}"
      end

      def database_pvc_name
        "data-db-#{@config.deploy.application.name}-0"
      end

      def database_secret_name
        "db-secret-#{@config.deploy.application.name}"
      end

      def database_pod_label
        "app=db-#{@config.deploy.application.name}"
      end

      def database_pod_name
        "db-#{@config.deploy.application.name}-0"
      end

      # ============================================================================
      # KUBERNETES APP RESOURCES
      # ============================================================================

      def app_deployment_name(service_name)
        "#{@config.deploy.application.name}-#{service_name}"
      end

      def app_service_name(service_name)
        "#{@config.deploy.application.name}-#{service_name}"
      end

      def app_secret_name
        "app-secret-#{@config.deploy.application.name}"
      end

      def app_pvc_name(volume_name)
        "#{@config.deploy.application.name}-#{volume_name}"
      end

      def app_ingress_name(service_name)
        "#{@config.deploy.application.name}-#{service_name}"
      end

      def app_pod_label(service_name)
        deployment_name = app_deployment_name(service_name)
        "app=#{deployment_name}"
      end

      def service_container_prefix(service_name)
        "#{@config.container_prefix}-#{service_name}-"
      end

      # ============================================================================
      # CLOUDFLARE RESOURCES
      # ============================================================================

      def tunnel_name(service_name)
        "#{@config.container_prefix}-#{service_name}"
      end

      def cloudflared_deployment_name(service_name)
        "cloudflared-#{service_name}"
      end

      # ============================================================================
      # REGISTRY RESOURCES
      # ============================================================================

      def registry_deployment_name
        "nvoi-registry"
      end

      def registry_service_name
        "nvoi-registry"
      end

      # ============================================================================
      # DEPLOYMENT RESOURCES
      # ============================================================================

      def deployment_lock_file_path
        "/tmp/nvoi-deploy-#{@config.container_prefix}.lock"
      end

      # ============================================================================
      # DOCKER IMAGE RESOURCES
      # ============================================================================

      def image_tag(timestamp)
        "#{@config.container_prefix}:#{timestamp}"
      end

      def latest_image_tag
        "#{@config.container_prefix}:latest"
      end

      # ============================================================================
      # VOLUME RESOURCES
      # ============================================================================

      # Server-level volume naming: {app}-{server}-{volume}
      def server_volume_name(server_name, volume_name)
        "#{@config.deploy.application.name}-#{server_name}-#{volume_name}"
      end

      # Host mount path for a server volume
      def server_volume_host_path(server_name, volume_name)
        "/opt/nvoi/volumes/#{server_volume_name(server_name, volume_name)}"
      end

      # ============================================================================
      # HOSTNAME HELPER
      # ============================================================================

      # Build full hostname from subdomain and domain
      def hostname(subdomain, domain)
        self.class.build_hostname(subdomain, domain)
      end

      # Class method for building hostname without instance
      def self.build_hostname(subdomain, domain)
        if subdomain.nil? || subdomain.empty? || subdomain == "@"
          domain
        else
          "#{subdomain}.#{domain}"
        end
      end

      private

        def hash_string(str)
          Digest::SHA256.hexdigest(str)[0, 16]
        end

        def infer_base_prefix
          output = `git config --get remote.origin.url 2>/dev/null`.strip
          return "app" if output.empty?

          # Extract username/repo from: git@github.com:user/repo.git or https://github.com/user/repo.git
          repo_url = output.sub(/\.git$/, "")
          parts = repo_url.split(%r{[/:]+})

          if parts.length >= 2
            username = parts[-2]
            repo = parts[-1]
            "#{username}-#{repo}"
          else
            "app"
          end
        end
    end
  end
end
