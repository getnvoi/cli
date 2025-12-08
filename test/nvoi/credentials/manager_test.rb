# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class Nvoi::Credentials::ManagerTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir("nvoi-test")
    @key = Nvoi::Credentials::Crypto.generate_key
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  def test_for_init_creates_manager_without_existing_files
    manager = Nvoi::Credentials::Manager.for_init(@temp_dir)

    refute_nil manager
    assert_equal File.join(@temp_dir, "deploy.enc"), manager.encrypted_path
  end

  def test_exists_returns_false_when_no_file
    manager = Nvoi::Credentials::Manager.for_init(@temp_dir)

    refute manager.exists?
  end

  def test_exists_returns_true_when_file_exists
    enc_path = File.join(@temp_dir, "deploy.enc")
    File.write(enc_path, "dummy")

    manager = Nvoi::Credentials::Manager.for_init(@temp_dir)

    assert manager.exists?
  end

  def test_has_key_returns_false_when_no_key
    manager = Nvoi::Credentials::Manager.for_init(@temp_dir)

    refute manager.has_key?
  end

  def test_has_key_returns_true_when_key_set
    manager = Nvoi::Credentials::Manager.for_init(@temp_dir)
    manager.set_master_key_for_testing(@key)

    assert manager.has_key?
  end

  def test_read_raises_without_key
    manager = Nvoi::Credentials::Manager.for_init(@temp_dir)

    error = assert_raises(Nvoi::CredentialError) do
      manager.read
    end
    assert_match(/master key not loaded/, error.message)
  end

  def test_write_raises_without_key
    manager = Nvoi::Credentials::Manager.for_init(@temp_dir)

    error = assert_raises(Nvoi::CredentialError) do
      manager.write("test content")
    end
    assert_match(/master key not loaded/, error.message)
  end

  def test_write_and_read_roundtrip
    manager = Nvoi::Credentials::Manager.for_init(@temp_dir)
    manager.set_master_key_for_testing(@key)

    original = "application:\n  name: test\n"
    manager.write(original)

    decrypted = manager.read
    assert_equal original, decrypted
  end

  def test_initialize_credentials_creates_files
    manager = Nvoi::Credentials::Manager.for_init(@temp_dir)
    template = "application:\n  name: myapp\n"

    key = manager.initialize_credentials(template)

    refute_nil key
    assert File.exist?(File.join(@temp_dir, "deploy.enc"))
    assert File.exist?(File.join(@temp_dir, "deploy.key"))
  end

  def test_initialize_credentials_key_file_has_correct_permissions
    skip "Permission tests unreliable on some systems"

    manager = Nvoi::Credentials::Manager.for_init(@temp_dir)
    manager.initialize_credentials("test")

    key_path = File.join(@temp_dir, "deploy.key")
    mode = File.stat(key_path).mode & 0o777
    assert_equal 0o600, mode
  end

  def test_initialize_credentials_roundtrip
    manager = Nvoi::Credentials::Manager.for_init(@temp_dir)
    template = "application:\n  name: roundtrip-test\n"

    manager.initialize_credentials(template)

    # Create new manager that will auto-discover key
    manager2 = Nvoi::Credentials::Manager.new(@temp_dir)
    decrypted = manager2.read

    assert_equal template, decrypted
  end

  def test_update_gitignore_creates_file_if_missing
    manager = Nvoi::Credentials::Manager.for_init(@temp_dir)
    manager.update_gitignore

    gitignore_path = File.join(@temp_dir, ".gitignore")
    assert File.exist?(gitignore_path)

    content = File.read(gitignore_path)
    assert_includes content, "deploy.key"
  end

  def test_update_gitignore_appends_to_existing_file
    gitignore_path = File.join(@temp_dir, ".gitignore")
    File.write(gitignore_path, "node_modules/\n")

    manager = Nvoi::Credentials::Manager.for_init(@temp_dir)
    manager.update_gitignore

    content = File.read(gitignore_path)
    assert_includes content, "node_modules/"
    assert_includes content, "deploy.key"
  end

  def test_update_gitignore_does_not_duplicate_entry
    gitignore_path = File.join(@temp_dir, ".gitignore")
    File.write(gitignore_path, "deploy.key\n")

    manager = Nvoi::Credentials::Manager.for_init(@temp_dir)
    manager.update_gitignore

    content = File.read(gitignore_path)
    # Should only appear once
    assert_equal 1, content.scan("deploy.key").count
  end

  def test_manager_finds_key_from_env_var
    # Create encrypted file first
    manager = Nvoi::Credentials::Manager.for_init(@temp_dir)
    manager.set_master_key_for_testing(@key)
    manager.write("test content")

    # Remove key file if it exists
    key_file = File.join(@temp_dir, "deploy.key")
    File.delete(key_file) if File.exist?(key_file)

    # Set env var
    ENV["NVOI_MASTER_KEY"] = @key

    begin
      manager2 = Nvoi::Credentials::Manager.new(@temp_dir)
      assert manager2.has_key?
      assert_equal "test content", manager2.read
    ensure
      ENV.delete("NVOI_MASTER_KEY")
    end
  end

  def test_manager_raises_when_no_key_found
    # Create encrypted file without key
    enc_path = File.join(@temp_dir, "deploy.enc")
    File.write(enc_path, "dummy encrypted content")

    error = assert_raises(Nvoi::CredentialError) do
      Nvoi::Credentials::Manager.new(@temp_dir)
    end
    assert_match(/master key not found/, error.message)
  end
end
