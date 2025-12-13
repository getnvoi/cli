# frozen_string_literal: true

module Nvoi
  module Utils
    # Default filenames
    DEFAULT_ENCRYPTED_FILE = "deploy.enc"
    DEFAULT_KEY_FILE = "deploy.key"
    MASTER_KEY_ENV_VAR = "NVOI_MASTER_KEY"

    # CredentialStore handles encrypted credentials file operations
    class CredentialStore
      attr_reader :encrypted_path, :key_path

      # Create a new credentials store
      # working_dir: base directory to search for files
      # encrypted_path: explicit path to encrypted file (optional, nil = auto-discover)
      # key_path: explicit path to key file (optional, nil = auto-discover)
      def initialize(working_dir, encrypted_path = nil, key_path = nil)
        @working_dir = working_dir
        @encrypted_path = encrypted_path.blank? ? find_encrypted_file : encrypted_path
        @key_path = nil
        @master_key = nil

        resolve_key(key_path)
      end

      # Create a store for initial setup (no existing files required)
      def self.for_init(working_dir)
        store = allocate
        store.instance_variable_set(:@working_dir, working_dir)
        store.instance_variable_set(:@encrypted_path, File.join(working_dir, DEFAULT_ENCRYPTED_FILE))
        store.instance_variable_set(:@key_path, nil)
        store.instance_variable_set(:@master_key, nil)
        store
      end

      # Check if the encrypted credentials file exists
      def exists?
        File.exist?(@encrypted_path)
      end

      # Check if the store has a master key loaded
      def has_key?
        !@master_key.blank?
      end

      # Decrypt and return the credentials content
      def read
        raise Errors::CredentialError, "master key not loaded" unless has_key?

        ciphertext = File.binread(@encrypted_path)
        Crypto.decrypt(ciphertext, @master_key)
      end

      # Encrypt and save the credentials content
      def write(plaintext)
        raise Errors::CredentialError, "master key not loaded" unless has_key?

        ciphertext = Crypto.encrypt(plaintext, @master_key)

        # Write atomically: write to temp file, then rename
        tmp_path = "#{@encrypted_path}.tmp"
        File.binwrite(tmp_path, ciphertext, perm: 0o600)

        begin
          File.rename(tmp_path, @encrypted_path)
        rescue StandardError => e
          File.delete(tmp_path) if File.exist?(tmp_path)
          raise Errors::CredentialError, "failed to rename temp file: #{e.message}"
        end
      end

      # Initialize creates a new encrypted credentials file with a generated key
      # Returns the generated key
      def initialize_credentials(template)
        # Generate new key
        @master_key = Crypto.generate_key

        # Write key file
        @key_path = File.join(File.dirname(@encrypted_path), DEFAULT_KEY_FILE)
        File.write(@key_path, "#{@master_key}\n", perm: 0o600)

        begin
          write(template)
        rescue StandardError => e
          File.delete(@key_path) if File.exist?(@key_path)
          raise e
        end

        @master_key
      end

      # Add deploy.key to .gitignore if not already present
      def update_gitignore
        gitignore_path = File.join(@working_dir, ".gitignore")

        content = File.exist?(gitignore_path) ? File.read(gitignore_path) : ""

        # Check if already present
        return if content.lines.any? { |line| line.strip == DEFAULT_KEY_FILE }

        File.open(gitignore_path, "a") do |f|
          # Add newline if file doesn't end with one
          f.write("\n") if !content.empty? && !content.end_with?("\n")

          # Add comment and entry
          f.write("\n# NVOI master key (do not commit)\n#{DEFAULT_KEY_FILE}\n")
        end
      end

      # For testing purposes
      def set_master_key_for_testing(key)
        @master_key = key
      end

      private

        def find_encrypted_file
          search_paths = [
            File.join(@working_dir, DEFAULT_ENCRYPTED_FILE),
            File.join(@working_dir, "config", DEFAULT_ENCRYPTED_FILE)
          ]

          search_paths.each do |path|
            return path if File.exist?(path)
          end

          # Default to working dir location (for new file creation)
          File.join(@working_dir, DEFAULT_ENCRYPTED_FILE)
        end

        def resolve_key(explicit_key_path)
          # Priority 1: Explicit key file path
          unless explicit_key_path.blank?
            @master_key = load_key_from_file(explicit_key_path)
            @key_path = explicit_key_path
            return
          end

          # Priority 2: Environment variable
          env_key = ENV[MASTER_KEY_ENV_VAR]
          unless env_key.blank?
            Crypto.validate_key(env_key)
            @master_key = env_key
            return
          end

          # Priority 3: Key file in standard locations
          key_search_paths = [
            File.join(File.dirname(@encrypted_path), DEFAULT_KEY_FILE),
            File.join(@working_dir, DEFAULT_KEY_FILE),
            File.join(@working_dir, "config", DEFAULT_KEY_FILE)
          ]

          key_search_paths.each do |path|
            next unless File.exist?(path)

            @master_key = load_key_from_file(path)
            @key_path = path
            return
          end

          raise Errors::CredentialError, "master key not found: set #{MASTER_KEY_ENV_VAR} or create #{DEFAULT_KEY_FILE}"
        end

        def load_key_from_file(path)
          content = File.read(path).strip
          Crypto.validate_key(content)
          content
        end
    end
  end
end
