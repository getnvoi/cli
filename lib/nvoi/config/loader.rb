# frozen_string_literal: true

module Nvoi
  module Config
    # ConfigLoader handles loading and initializing configuration
    class ConfigLoader
      attr_accessor :credentials_path, :master_key_path

      def initialize
        @credentials_path = nil
        @master_key_path = nil
      end

      # Set explicit path to encrypted credentials file
      def with_credentials_path(path)
        @credentials_path = path
        self
      end

      # Set explicit path to master key file
      def with_master_key_path(path)
        @master_key_path = path
        self
      end

      # Load reads and parses the deployment configuration from encrypted file
      def load(config_path)
        # Determine working directory
        working_dir = config_path && !config_path.empty? ? File.dirname(config_path) : "."

        # Use explicit credentials path or derive from config_path
        enc_path = @credentials_path
        enc_path = config_path if enc_path.nil? || enc_path.empty?

        # Create credentials manager
        manager = Credentials::Manager.new(working_dir, enc_path, @master_key_path)

        # Decrypt credentials
        plaintext = manager.read
        raise ConfigError, "Failed to decrypt credentials" unless plaintext

        # Parse YAML
        data = YAML.safe_load(plaintext, permitted_classes: [Symbol])
        raise ConfigError, "Invalid config format" unless data.is_a?(Hash)

        deploy_config = DeployConfig.new(data)

        # Create config
        cfg = Configuration.new(deploy_config)

        # Load SSH keys
        key_locator = SSHKeyLocator.new(cfg)
        key_locator.load_keys

        # Validate config structure
        cfg.validate_config

        # Generate resource names
        namer = ResourceNamer.new(cfg)
        cfg.container_prefix = namer.infer_container_prefix
        master_group = find_master_server_group(cfg)
        cfg.server_name = namer.server_name(master_group, 1)
        cfg.firewall_name = namer.firewall_name
        cfg.network_name = namer.network_name
        cfg.docker_network_name = namer.docker_network_name

        cfg
      end

      private

      def find_master_server_group(cfg)
        servers = cfg.deploy.application.servers
        return "master" if servers.empty?

        # Find explicit master
        servers.each do |name, server_cfg|
          return name if server_cfg&.master
        end

        # Single server group: use it as master
        return servers.keys.first if servers.size == 1

        # Fallback
        "master"
      end
    end

    # Module-level load function
    def self.load(config_path)
      ConfigLoader.new.load(config_path)
    end

    # Module-level load with explicit key paths
    def self.load_with_keys(config_path, credentials_path, master_key_path)
      ConfigLoader.new
                  .with_credentials_path(credentials_path)
                  .with_master_key_path(master_key_path)
                  .load(config_path)
    end
  end
end
