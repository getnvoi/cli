# frozen_string_literal: true

require "test_helper"

class CryptoTest < Minitest::Test
  def test_generate_key
    key = Nvoi::Utils::Crypto.generate_key
    assert_equal 64, key.length
    assert_match(/\A[0-9a-f]+\z/, key)
  end

  def test_encrypt_decrypt_roundtrip
    key = Nvoi::Utils::Crypto.generate_key
    plaintext = "hello world"

    ciphertext = Nvoi::Utils::Crypto.encrypt(plaintext, key)
    decrypted = Nvoi::Utils::Crypto.decrypt(ciphertext, key)

    assert_equal plaintext, decrypted
  end

  def test_encrypt_produces_different_output_each_time
    key = Nvoi::Utils::Crypto.generate_key
    plaintext = "hello world"

    ciphertext1 = Nvoi::Utils::Crypto.encrypt(plaintext, key)
    ciphertext2 = Nvoi::Utils::Crypto.encrypt(plaintext, key)

    refute_equal ciphertext1, ciphertext2
  end

  def test_decrypt_with_wrong_key_fails
    key1 = Nvoi::Utils::Crypto.generate_key
    key2 = Nvoi::Utils::Crypto.generate_key
    plaintext = "secret data"

    ciphertext = Nvoi::Utils::Crypto.encrypt(plaintext, key1)

    assert_raises(Nvoi::DecryptionError) do
      Nvoi::Utils::Crypto.decrypt(ciphertext, key2)
    end
  end

  def test_decrypt_corrupted_data_fails
    key = Nvoi::Utils::Crypto.generate_key
    plaintext = "hello world"

    ciphertext = Nvoi::Utils::Crypto.encrypt(plaintext, key)
    corrupted = ciphertext.dup
    corrupted[20] = (corrupted[20].ord ^ 0xFF).chr

    assert_raises(Nvoi::DecryptionError) do
      Nvoi::Utils::Crypto.decrypt(corrupted, key)
    end
  end

  def test_validate_key_valid
    key = Nvoi::Utils::Crypto.generate_key
    assert Nvoi::Utils::Crypto.validate_key(key)
  end

  def test_validate_key_wrong_length
    assert_raises(Nvoi::InvalidKeyError) do
      Nvoi::Utils::Crypto.validate_key("abc123")
    end
  end

  def test_validate_key_invalid_characters
    invalid_key = "g" * 64 # 'g' is not a hex character
    assert_raises(Nvoi::InvalidKeyError) do
      Nvoi::Utils::Crypto.validate_key(invalid_key)
    end
  end

  def test_decrypt_too_short_ciphertext
    key = Nvoi::Utils::Crypto.generate_key

    assert_raises(Nvoi::DecryptionError) do
      Nvoi::Utils::Crypto.decrypt("short", key)
    end
  end

  def test_encrypt_empty_string
    key = Nvoi::Utils::Crypto.generate_key
    plaintext = ""

    ciphertext = Nvoi::Utils::Crypto.encrypt(plaintext, key)
    decrypted = Nvoi::Utils::Crypto.decrypt(ciphertext, key)

    assert_equal plaintext, decrypted
  end

  def test_encrypt_unicode
    key = Nvoi::Utils::Crypto.generate_key
    plaintext = "こんにちは世界 🌍"

    ciphertext = Nvoi::Utils::Crypto.encrypt(plaintext, key)
    decrypted = Nvoi::Utils::Crypto.decrypt(ciphertext, key)

    # Force UTF-8 encoding for comparison
    assert_equal plaintext, decrypted.force_encoding("UTF-8")
  end
end
