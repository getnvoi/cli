# frozen_string_literal: true

require "tempfile"
require "fileutils"

module Nvoi
  module Config
    # SSHKeyLoader handles SSH key loading from config content
    # Keys are stored as content in deploy.enc, written to temp files for SSH usage
    class SSHKeyLoader
      def initialize(config)
        @config = config
        @temp_dir = nil
        @private_key_path = nil
        @public_key_path = nil
      end

      # Load SSH keys from config content and write to temp files
      def load_keys
        ssh_keys = @config.deploy.application.ssh_keys

        unless ssh_keys
          raise ConfigError, "ssh_keys section is required in config. Run 'nvoi credentials edit' to generate keys."
        end

        unless ssh_keys.private_key && !ssh_keys.private_key.empty?
          raise ConfigError, "ssh_keys.private_key is required"
        end

        unless ssh_keys.public_key && !ssh_keys.public_key.empty?
          raise ConfigError, "ssh_keys.public_key is required"
        end

        # Create temp directory for keys
        @temp_dir = Dir.mktmpdir("nvoi-ssh-")

        # Write private key
        @private_key_path = File.join(@temp_dir, "id_nvoi")
        File.write(@private_key_path, ssh_keys.private_key)
        File.chmod(0o600, @private_key_path)

        # Write public key
        @public_key_path = File.join(@temp_dir, "id_nvoi.pub")
        File.write(@public_key_path, ssh_keys.public_key)
        File.chmod(0o644, @public_key_path)

        # Set config values
        @config.ssh_key_path = @private_key_path
        @config.ssh_public_key = ssh_keys.public_key.strip
      end

      # Cleanup temp files
      def cleanup
        FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
      end

      class << self
        # Generate a new Ed25519 keypair using ssh-keygen
        def generate_keypair
          temp_dir = Dir.mktmpdir("nvoi-keygen-")
          key_path = File.join(temp_dir, "id_nvoi")

          begin
            result = system(
              "ssh-keygen", "-t", "ed25519", "-N", "", "-C", "nvoi-deploy", "-f", key_path,
              out: File::NULL, err: File::NULL
            )

            raise ConfigError, "Failed to generate SSH keypair (ssh-keygen not available?)" unless result

            private_key = File.read(key_path)
            public_key = File.read("#{key_path}.pub").strip

            [private_key, public_key]
          ensure
            FileUtils.rm_rf(temp_dir)
          end
        end
      end
    end
  end
end
