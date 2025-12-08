# frozen_string_literal: true

require "test_helper"

class Nvoi::Credentials::CryptoTest < Minitest::Test
  def test_generate_key_returns_64_hex_chars
    key = Nvoi::Credentials::Crypto.generate_key
    assert_equal 64, key.length
    assert_match(/\A[0-9a-f]+\z/, key)
  end

  def test_generate_key_is_unique
    keys = 10.times.map { Nvoi::Credentials::Crypto.generate_key }
    assert_equal 10, keys.uniq.length
  end

  def test_validate_key_accepts_valid_keys
    key = Nvoi::Credentials::Crypto.generate_key
    assert Nvoi::Credentials::Crypto.validate_key(key)
  end

  def test_validate_key_rejects_short_keys
    assert_raises(Nvoi::InvalidKeyError) do
      Nvoi::Credentials::Crypto.validate_key("abc123")
    end
  end

  def test_validate_key_rejects_long_keys
    assert_raises(Nvoi::InvalidKeyError) do
      Nvoi::Credentials::Crypto.validate_key("a" * 128)
    end
  end

  def test_validate_key_rejects_non_hex
    assert_raises(Nvoi::InvalidKeyError) do
      Nvoi::Credentials::Crypto.validate_key("g" * 64)
    end
  end

  def test_encrypt_and_decrypt_roundtrip
    key = Nvoi::Credentials::Crypto.generate_key
    plaintext = "Hello, World! This is a secret message."

    ciphertext = Nvoi::Credentials::Crypto.encrypt(plaintext, key)
    decrypted = Nvoi::Credentials::Crypto.decrypt(ciphertext, key)

    assert_equal plaintext, decrypted
  end

  def test_encrypt_produces_different_ciphertext_each_time
    key = Nvoi::Credentials::Crypto.generate_key
    plaintext = "Same message"

    ciphertext1 = Nvoi::Credentials::Crypto.encrypt(plaintext, key)
    ciphertext2 = Nvoi::Credentials::Crypto.encrypt(plaintext, key)

    refute_equal ciphertext1, ciphertext2
  end

  def test_decrypt_fails_with_wrong_key
    key1 = Nvoi::Credentials::Crypto.generate_key
    key2 = Nvoi::Credentials::Crypto.generate_key
    plaintext = "Secret data"

    ciphertext = Nvoi::Credentials::Crypto.encrypt(plaintext, key1)

    assert_raises(Nvoi::DecryptionError) do
      Nvoi::Credentials::Crypto.decrypt(ciphertext, key2)
    end
  end

  def test_decrypt_fails_with_corrupted_ciphertext
    key = Nvoi::Credentials::Crypto.generate_key
    plaintext = "Secret data"

    ciphertext = Nvoi::Credentials::Crypto.encrypt(plaintext, key)
    corrupted = ciphertext.dup
    corrupted[20] = (corrupted[20].ord ^ 0xFF).chr

    assert_raises(Nvoi::DecryptionError) do
      Nvoi::Credentials::Crypto.decrypt(corrupted, key)
    end
  end

  def test_decrypt_fails_with_truncated_ciphertext
    key = Nvoi::Credentials::Crypto.generate_key

    assert_raises(Nvoi::DecryptionError) do
      Nvoi::Credentials::Crypto.decrypt("too short", key)
    end
  end

  def test_handles_empty_plaintext
    key = Nvoi::Credentials::Crypto.generate_key

    ciphertext = Nvoi::Credentials::Crypto.encrypt("", key)
    decrypted = Nvoi::Credentials::Crypto.decrypt(ciphertext, key)

    assert_equal "", decrypted
  end

  def test_handles_binary_data
    key = Nvoi::Credentials::Crypto.generate_key
    binary = (0..255).map(&:chr).join

    ciphertext = Nvoi::Credentials::Crypto.encrypt(binary, key)
    decrypted = Nvoi::Credentials::Crypto.decrypt(ciphertext, key)

    assert_equal binary, decrypted
  end

  def test_handles_large_plaintext
    key = Nvoi::Credentials::Crypto.generate_key
    large_data = "x" * 1_000_000 # 1MB

    ciphertext = Nvoi::Credentials::Crypto.encrypt(large_data, key)
    decrypted = Nvoi::Credentials::Crypto.decrypt(ciphertext, key)

    assert_equal large_data, decrypted
  end

  def test_handles_unicode_plaintext
    key = Nvoi::Credentials::Crypto.generate_key
    unicode = "Hello World!"

    ciphertext = Nvoi::Credentials::Crypto.encrypt(unicode, key)
    decrypted = Nvoi::Credentials::Crypto.decrypt(ciphertext, key)

    assert_equal unicode, decrypted
  end

  def test_ciphertext_format_has_nonce_and_tag
    key = Nvoi::Credentials::Crypto.generate_key
    plaintext = "test"

    ciphertext = Nvoi::Credentials::Crypto.encrypt(plaintext, key)

    # Format: 12-byte nonce + ciphertext + 16-byte auth tag
    # Minimum size = 12 + 0 + 16 = 28 bytes
    assert ciphertext.bytesize >= 28
    # With "test" (4 bytes), should be 12 + 4 + 16 = 32
    assert_equal 32, ciphertext.bytesize
  end

  def test_accepts_uppercase_hex_key
    lowercase_key = Nvoi::Credentials::Crypto.generate_key
    uppercase_key = lowercase_key.upcase
    plaintext = "test message"

    ciphertext = Nvoi::Credentials::Crypto.encrypt(plaintext, uppercase_key)
    decrypted = Nvoi::Credentials::Crypto.decrypt(ciphertext, uppercase_key)

    assert_equal plaintext, decrypted
  end

  def test_accepts_mixed_case_hex_key
    key = Nvoi::Credentials::Crypto.generate_key
    mixed_key = key.chars.each_with_index.map { |c, i| i.even? ? c.upcase : c.downcase }.join
    plaintext = "test message"

    ciphertext = Nvoi::Credentials::Crypto.encrypt(plaintext, mixed_key)
    decrypted = Nvoi::Credentials::Crypto.decrypt(ciphertext, mixed_key)

    assert_equal plaintext, decrypted
  end
end
