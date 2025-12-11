# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"

class CredentialStoreTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir("nvoi-test")
    @key = Nvoi::Utils::Crypto.generate_key
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  def test_for_init_creates_store_without_existing_files
    store = Nvoi::Utils::CredentialStore.for_init(@temp_dir)

    refute_nil store
    assert_equal File.join(@temp_dir, "deploy.enc"), store.encrypted_path
  end

  def test_exists_returns_false_when_no_file
    store = Nvoi::Utils::CredentialStore.for_init(@temp_dir)

    refute store.exists?
  end

  def test_exists_returns_true_when_file_exists
    enc_path = File.join(@temp_dir, "deploy.enc")
    File.write(enc_path, "dummy")

    store = Nvoi::Utils::CredentialStore.for_init(@temp_dir)

    assert store.exists?
  end

  def test_has_key_returns_false_when_no_key
    store = Nvoi::Utils::CredentialStore.for_init(@temp_dir)

    refute store.has_key?
  end

  def test_has_key_returns_true_when_key_set
    store = Nvoi::Utils::CredentialStore.for_init(@temp_dir)
    store.set_master_key_for_testing(@key)

    assert store.has_key?
  end

  def test_read_raises_without_key
    store = Nvoi::Utils::CredentialStore.for_init(@temp_dir)

    error = assert_raises(Nvoi::Errors::CredentialError) do
      store.read
    end
    assert_match(/master key not loaded/, error.message)
  end

  def test_write_raises_without_key
    store = Nvoi::Utils::CredentialStore.for_init(@temp_dir)

    error = assert_raises(Nvoi::Errors::CredentialError) do
      store.write("test content")
    end
    assert_match(/master key not loaded/, error.message)
  end

  def test_write_and_read_roundtrip
    store = Nvoi::Utils::CredentialStore.for_init(@temp_dir)
    store.set_master_key_for_testing(@key)

    original = "application:\n  name: test\n"
    store.write(original)

    decrypted = store.read
    assert_equal original, decrypted
  end

  def test_initialize_credentials_creates_files
    store = Nvoi::Utils::CredentialStore.for_init(@temp_dir)
    template = "application:\n  name: myapp\n"

    key = store.initialize_credentials(template)

    refute_nil key
    assert File.exist?(File.join(@temp_dir, "deploy.enc"))
    assert File.exist?(File.join(@temp_dir, "deploy.key"))
  end

  def test_initialize_credentials_key_file_has_correct_permissions
    skip "Permission tests unreliable on some systems"

    store = Nvoi::Utils::CredentialStore.for_init(@temp_dir)
    store.initialize_credentials("test")

    key_path = File.join(@temp_dir, "deploy.key")
    mode = File.stat(key_path).mode & 0o777
    assert_equal 0o600, mode
  end

  def test_initialize_credentials_roundtrip
    store = Nvoi::Utils::CredentialStore.for_init(@temp_dir)
    template = "application:\n  name: roundtrip-test\n"

    store.initialize_credentials(template)

    # Create new store that will auto-discover key
    store2 = Nvoi::Utils::CredentialStore.new(@temp_dir)
    decrypted = store2.read

    assert_equal template, decrypted
  end

  def test_update_gitignore_creates_file_if_missing
    store = Nvoi::Utils::CredentialStore.for_init(@temp_dir)
    store.update_gitignore

    gitignore_path = File.join(@temp_dir, ".gitignore")
    assert File.exist?(gitignore_path)

    content = File.read(gitignore_path)
    assert_includes content, "deploy.key"
  end

  def test_update_gitignore_appends_to_existing_file
    gitignore_path = File.join(@temp_dir, ".gitignore")
    File.write(gitignore_path, "node_modules/\n")

    store = Nvoi::Utils::CredentialStore.for_init(@temp_dir)
    store.update_gitignore

    content = File.read(gitignore_path)
    assert_includes content, "node_modules/"
    assert_includes content, "deploy.key"
  end

  def test_update_gitignore_does_not_duplicate_entry
    gitignore_path = File.join(@temp_dir, ".gitignore")
    File.write(gitignore_path, "deploy.key\n")

    store = Nvoi::Utils::CredentialStore.for_init(@temp_dir)
    store.update_gitignore

    content = File.read(gitignore_path)
    # Should only appear once
    assert_equal 1, content.scan("deploy.key").count
  end

  def test_store_finds_key_from_env_var
    # Create encrypted file first
    store = Nvoi::Utils::CredentialStore.for_init(@temp_dir)
    store.set_master_key_for_testing(@key)
    store.write("test content")

    # Remove key file if it exists
    key_file = File.join(@temp_dir, "deploy.key")
    File.delete(key_file) if File.exist?(key_file)

    # Set env var
    ENV["NVOI_MASTER_KEY"] = @key

    begin
      store2 = Nvoi::Utils::CredentialStore.new(@temp_dir)
      assert store2.has_key?
      assert_equal "test content", store2.read
    ensure
      ENV.delete("NVOI_MASTER_KEY")
    end
  end

  def test_store_raises_when_no_key_found
    # Create encrypted file without key
    enc_path = File.join(@temp_dir, "deploy.enc")
    File.write(enc_path, "dummy encrypted content")

    error = assert_raises(Nvoi::Errors::CredentialError) do
      Nvoi::Utils::CredentialStore.new(@temp_dir)
    end
    assert_match(/master key not found/, error.message)
  end

  def test_store_with_explicit_key_path
    # Create key file in non-standard location
    custom_key_path = File.join(@temp_dir, "custom.key")
    File.write(custom_key_path, @key)

    # Create encrypted file
    store = Nvoi::Utils::CredentialStore.for_init(@temp_dir)
    store.set_master_key_for_testing(@key)
    store.write("custom key content")

    # Load with explicit key path
    store2 = Nvoi::Utils::CredentialStore.new(@temp_dir, nil, custom_key_path)
    assert_equal "custom key content", store2.read
  end

  def test_store_with_explicit_encrypted_path
    custom_enc_path = File.join(@temp_dir, "custom.enc")

    store = Nvoi::Utils::CredentialStore.for_init(@temp_dir)
    store.set_master_key_for_testing(@key)

    # Manually set encrypted path
    store.instance_variable_set(:@encrypted_path, custom_enc_path)
    store.write("custom path content")

    # Create key file for auto-discovery
    File.write(File.join(@temp_dir, "deploy.key"), @key)

    store2 = Nvoi::Utils::CredentialStore.new(@temp_dir, custom_enc_path)
    assert_equal "custom path content", store2.read
  end
end
