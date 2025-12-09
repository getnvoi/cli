# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class Nvoi::Config::SSHKeyLoaderTest < Minitest::Test
  def test_load_keys_writes_temp_files
    config = mock_config_with_keys(
      private_key: "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----",
      public_key: "ssh-ed25519 AAAAC3test nvoi-deploy"
    )

    loader = Nvoi::Config::SSHKeyLoader.new(config)
    loader.load_keys

    # Verify temp files created
    assert File.exist?(config.ssh_key_path), "Private key file should exist"
    assert_equal "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----",
                 File.read(config.ssh_key_path)

    # Verify permissions
    assert_equal 0o600, File.stat(config.ssh_key_path).mode & 0o777

    # Verify public key set
    assert_equal "ssh-ed25519 AAAAC3test nvoi-deploy", config.ssh_public_key

    loader.cleanup
  end

  def test_load_keys_raises_if_no_ssh_keys_section
    config = mock_config_with_keys(private_key: nil, public_key: nil, no_keys: true)

    loader = Nvoi::Config::SSHKeyLoader.new(config)

    assert_raises(Nvoi::ConfigError) do
      loader.load_keys
    end
  end

  def test_load_keys_raises_if_private_key_missing
    config = mock_config_with_keys(private_key: nil, public_key: "ssh-ed25519 test")

    loader = Nvoi::Config::SSHKeyLoader.new(config)

    error = assert_raises(Nvoi::ConfigError) do
      loader.load_keys
    end
    assert_match(/private_key/, error.message)
  end

  def test_load_keys_raises_if_public_key_missing
    config = mock_config_with_keys(
      private_key: "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----",
      public_key: nil
    )

    loader = Nvoi::Config::SSHKeyLoader.new(config)

    error = assert_raises(Nvoi::ConfigError) do
      loader.load_keys
    end
    assert_match(/public_key/, error.message)
  end

  def test_cleanup_removes_temp_directory
    config = mock_config_with_keys(
      private_key: "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----",
      public_key: "ssh-ed25519 test nvoi-deploy"
    )

    loader = Nvoi::Config::SSHKeyLoader.new(config)
    loader.load_keys

    temp_dir = File.dirname(config.ssh_key_path)
    assert Dir.exist?(temp_dir)

    loader.cleanup

    refute Dir.exist?(temp_dir)
  end

  def test_strips_whitespace_from_public_key
    config = mock_config_with_keys(
      private_key: "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----",
      public_key: "  ssh-ed25519 test nvoi-deploy  \n"
    )

    loader = Nvoi::Config::SSHKeyLoader.new(config)
    loader.load_keys

    assert_equal "ssh-ed25519 test nvoi-deploy", config.ssh_public_key

    loader.cleanup
  end

  private

    def mock_config_with_keys(private_key:, public_key:, no_keys: false)
      ssh_keys = if no_keys
        nil
      else
        MockSSHKeyConfig.new(private_key:, public_key:)
      end

      MockConfig.new(
        deploy: MockDeploy.new(
          application: MockApplication.new(
            name: "myapp",
            ssh_keys:,
            servers: {},
            app: {},
            database: nil,
            services: {}
          )
        ),
        container_prefix: "test",
        ssh_key_path: nil,
        ssh_public_key: nil
      )
    end
end

class Nvoi::Config::SSHKeyGenerationTest < Minitest::Test
  def test_generate_keypair_returns_valid_keys
    private_key, public_key = Nvoi::Config::SSHKeyLoader.generate_keypair

    # Private key should be OpenSSH format
    assert private_key.start_with?("-----BEGIN OPENSSH PRIVATE KEY-----")
    assert private_key.include?("-----END OPENSSH PRIVATE KEY-----")

    # Public key should be ssh-ed25519 format
    assert public_key.start_with?("ssh-ed25519 ")
    assert public_key.include?("nvoi-deploy")
  end

  def test_generate_keypair_creates_unique_keys
    key1_priv, key1_pub = Nvoi::Config::SSHKeyLoader.generate_keypair
    key2_priv, key2_pub = Nvoi::Config::SSHKeyLoader.generate_keypair

    refute_equal key1_priv, key2_priv
    refute_equal key1_pub, key2_pub
  end
end
