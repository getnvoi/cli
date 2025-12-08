# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class Nvoi::Config::SSHKeyLocatorTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir("nvoi-test-ssh")
    @ssh_dir = File.join(@temp_dir, ".ssh")
    FileUtils.mkdir_p(@ssh_dir)
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  def test_load_keys_with_explicit_paths
    # Create test key files
    private_key_path = File.join(@ssh_dir, "custom_key")
    public_key_path = File.join(@ssh_dir, "custom_key.pub")

    File.write(private_key_path, "PRIVATE KEY CONTENT")
    File.write(public_key_path, "ssh-rsa AAAAB3... user@host")

    config = mock_config_with_ssh_paths(private_key_path, public_key_path)
    locator = Nvoi::Config::SSHKeyLocator.new(config)

    locator.load_keys

    assert_equal private_key_path, config.ssh_key_path
    assert_equal "ssh-rsa AAAAB3... user@host", config.ssh_public_key
  end

  def test_load_keys_derives_public_from_private
    # Create test key files
    private_key_path = File.join(@ssh_dir, "my_key")
    public_key_path = File.join(@ssh_dir, "my_key.pub")

    File.write(private_key_path, "PRIVATE KEY CONTENT")
    File.write(public_key_path, "ssh-ed25519 AAAAC3... user@host")

    config = mock_config_with_ssh_paths(private_key_path, nil)
    locator = Nvoi::Config::SSHKeyLocator.new(config)

    locator.load_keys

    assert_equal private_key_path, config.ssh_key_path
    assert_equal "ssh-ed25519 AAAAC3... user@host", config.ssh_public_key
  end

  def test_load_keys_from_env_variable
    private_key_path = File.join(@ssh_dir, "env_key")
    public_key_path = File.join(@ssh_dir, "env_key.pub")

    File.write(private_key_path, "PRIVATE KEY")
    File.write(public_key_path, "ssh-rsa ENVKEY user@host")

    config = mock_config_with_ssh_paths(nil, nil)
    locator = Nvoi::Config::SSHKeyLocator.new(config)

    # Mock ENV
    original_env = ENV["SSH_KEY_PATH"]
    ENV["SSH_KEY_PATH"] = private_key_path

    begin
      locator.load_keys
      assert_equal private_key_path, config.ssh_key_path
      assert_equal "ssh-rsa ENVKEY user@host", config.ssh_public_key
    ensure
      if original_env
        ENV["SSH_KEY_PATH"] = original_env
      else
        ENV.delete("SSH_KEY_PATH")
      end
    end
  end

  def test_load_keys_raises_if_public_key_missing
    private_key_path = File.join(@ssh_dir, "lonely_key")
    File.write(private_key_path, "PRIVATE KEY")
    # No public key file

    config = mock_config_with_ssh_paths(private_key_path, nil)
    locator = Nvoi::Config::SSHKeyLocator.new(config)

    assert_raises(Nvoi::ConfigError) do
      locator.load_keys
    end
  end

  def test_finds_id_rsa_by_default
    # Create id_rsa key
    private_key = File.join(@ssh_dir, "id_rsa")
    public_key = File.join(@ssh_dir, "id_rsa.pub")

    File.write(private_key, "RSA PRIVATE KEY")
    File.write(public_key, "ssh-rsa DEFAULT user@host")

    config = mock_config_with_ssh_paths(nil, nil)
    locator = Nvoi::Config::SSHKeyLocator.new(config)

    # Mock Dir.home to return our temp dir
    Dir.stub(:home, @temp_dir) do
      locator.load_keys
      assert_equal private_key, config.ssh_key_path
      assert_equal "ssh-rsa DEFAULT user@host", config.ssh_public_key
    end
  end

  def test_finds_id_ed25519_if_no_id_rsa
    # Create only id_ed25519 key
    private_key = File.join(@ssh_dir, "id_ed25519")
    public_key = File.join(@ssh_dir, "id_ed25519.pub")

    File.write(private_key, "ED25519 PRIVATE KEY")
    File.write(public_key, "ssh-ed25519 EDKEY user@host")

    config = mock_config_with_ssh_paths(nil, nil)
    locator = Nvoi::Config::SSHKeyLocator.new(config)

    Dir.stub(:home, @temp_dir) do
      locator.load_keys
      assert_equal private_key, config.ssh_key_path
      assert_equal "ssh-ed25519 EDKEY user@host", config.ssh_public_key
    end
  end

  def test_expands_tilde_in_path
    # Create test files in temp ssh dir
    private_key = File.join(@ssh_dir, "custom_key")
    public_key = File.join(@ssh_dir, "custom_key.pub")

    File.write(private_key, "PRIVATE")
    File.write(public_key, "ssh-rsa TILDEKEY user@host")

    # Config with tilde path
    config = mock_config_with_ssh_paths("~/.ssh/custom_key", nil)
    locator = Nvoi::Config::SSHKeyLocator.new(config)

    Dir.stub(:home, @temp_dir) do
      locator.load_keys
      assert_equal private_key, config.ssh_key_path
    end
  end

  def test_strips_whitespace_from_public_key
    private_key = File.join(@ssh_dir, "key")
    public_key = File.join(@ssh_dir, "key.pub")

    File.write(private_key, "PRIVATE")
    File.write(public_key, "  ssh-rsa KEYDATA user@host  \n")

    config = mock_config_with_ssh_paths(private_key, nil)
    locator = Nvoi::Config::SSHKeyLocator.new(config)

    locator.load_keys

    assert_equal "ssh-rsa KEYDATA user@host", config.ssh_public_key
    refute config.ssh_public_key.include?("\n")
    refute config.ssh_public_key.start_with?(" ")
  end

  private

    def mock_config_with_ssh_paths(private_path, public_path)
      ssh_key_path = if private_path || public_path
        MockSSHKeyPath.new(private: private_path, public: public_path)
      else
        nil
      end

      MockConfig.new(
        deploy: MockDeploy.new(
          application: MockApplication.new(
            name: "myapp",
            ssh_key_path:,
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

class Nvoi::Config::SSHKeyGenerationMockTest < Minitest::Test
  # Tests for mocked SSH key generation scenarios

  def test_generates_valid_ssh_key_format
    # Simulate generated key formats
    rsa_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC#{SecureRandom.base64(100).gsub(/[^A-Za-z0-9]/, '')} test@nvoi"
    ed25519_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI#{SecureRandom.base64(32).gsub(/[^A-Za-z0-9]/, '')} test@nvoi"

    # Verify RSA format
    assert_match(/^ssh-rsa AAAA[A-Za-z0-9+\/]+ .+$/, rsa_key)

    # Verify Ed25519 format
    assert_match(/^ssh-ed25519 AAAA[A-Za-z0-9+\/]+ .+$/, ed25519_key)
  end

  def test_key_types_supported
    supported = %w[id_rsa id_ed25519 id_ecdsa id_dsa]

    supported.each do |key_type|
      assert_match(/^id_/, key_type)
    end
  end
end
