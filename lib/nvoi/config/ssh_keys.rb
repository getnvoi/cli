# frozen_string_literal: true

module Nvoi
  module Config
    # SSHKeyLocator handles SSH key location and loading
    class SSHKeyLocator
      def initialize(config)
        @config = config
      end

      # Load SSH key paths and public key content
      def load_keys
        # Determine private key path
        @config.ssh_key_path = determine_private_key_path

        # Determine public key path
        pub_key_path = determine_public_key_path

        # Read public key
        unless File.exist?(pub_key_path)
          raise ConfigError, "SSH public key not found: #{pub_key_path}"
        end

        @config.ssh_public_key = File.read(pub_key_path).strip
      end

      private

      def determine_private_key_path
        ssh_config = @config.deploy.application.ssh_key_path

        if ssh_config&.private && !ssh_config.private.empty?
          expand_path(ssh_config.private)
        elsif ENV["SSH_KEY_PATH"] && !ENV["SSH_KEY_PATH"].empty?
          expand_path(ENV["SSH_KEY_PATH"])
        else
          find_ssh_key
        end
      end

      def determine_public_key_path
        ssh_config = @config.deploy.application.ssh_key_path

        if ssh_config&.public && !ssh_config.public.empty?
          expand_path(ssh_config.public)
        else
          "#{@config.ssh_key_path}.pub"
        end
      end

      def find_ssh_key
        home_dir = Dir.home
        ssh_dir = File.join(home_dir, ".ssh")

        key_names = %w[id_rsa id_ed25519 id_ecdsa id_dsa]
        key_names.each do |name|
          path = File.join(ssh_dir, name)
          return path if File.exist?(path)
        end

        # Return default path even if it doesn't exist
        File.join(ssh_dir, "id_rsa")
      end

      def expand_path(path)
        return path unless path.start_with?("~/")

        File.join(Dir.home, path[2..])
      end
    end
  end
end
