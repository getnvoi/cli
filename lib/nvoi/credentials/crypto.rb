# frozen_string_literal: true

module Nvoi
  module Credentials
    # Crypto handles AES-256-GCM encryption/decryption
    module Crypto
      KEY_SIZE = 32 # 256 bits
      NONCE_SIZE = 12 # GCM nonce size
      KEY_HEX_LENGTH = KEY_SIZE * 2 # 64 hex characters

      class << self
        # Generate a new random 32-byte key and return it as hex string
        def generate_key
          SecureRandom.hex(KEY_SIZE)
        end

        # Encrypt plaintext using AES-256-GCM with the provided hex-encoded key
        # Returns: [12-byte nonce][ciphertext][16-byte auth tag]
        def encrypt(plaintext, hex_key)
          key = decode_key(hex_key)

          cipher = OpenSSL::Cipher.new("aes-256-gcm")
          cipher.encrypt
          cipher.key = key

          # Generate random nonce
          nonce = SecureRandom.random_bytes(NONCE_SIZE)
          cipher.iv = nonce

          # Encrypt
          ciphertext = cipher.update(plaintext) + cipher.final
          auth_tag = cipher.auth_tag

          # Return: nonce + ciphertext + auth_tag
          nonce + ciphertext + auth_tag
        end

        # Decrypt ciphertext using AES-256-GCM with the provided hex-encoded key
        # Expects format: [12-byte nonce][ciphertext][16-byte auth tag]
        def decrypt(ciphertext, hex_key)
          key = decode_key(hex_key)

          min_size = NONCE_SIZE + 16 # nonce + auth tag
          if ciphertext.bytesize < min_size
            raise DecryptionError, "ciphertext too short: need at least #{min_size} bytes, got #{ciphertext.bytesize}"
          end

          # Extract nonce and auth tag
          nonce = ciphertext[0, NONCE_SIZE]
          auth_tag = ciphertext[-16, 16]
          encrypted_data = ciphertext[NONCE_SIZE...-16]

          cipher = OpenSSL::Cipher.new("aes-256-gcm")
          cipher.decrypt
          cipher.key = key
          cipher.iv = nonce
          cipher.auth_tag = auth_tag

          begin
            cipher.update(encrypted_data) + cipher.final
          rescue OpenSSL::Cipher::CipherError => e
            raise DecryptionError, "decryption failed (wrong key or corrupted data): #{e.message}"
          end
        end

        # Validate a hex-encoded key
        def validate_key(hex_key)
          unless hex_key.length == KEY_HEX_LENGTH
            raise InvalidKeyError, "invalid key length: expected #{KEY_HEX_LENGTH} hex characters, got #{hex_key.length}"
          end

          unless hex_key.match?(/\A[0-9a-fA-F]+\z/)
            raise InvalidKeyError, "invalid hex key: contains non-hex characters"
          end

          true
        end

        private

          def decode_key(hex_key)
            validate_key(hex_key)
            [hex_key].pack("H*")
          end
      end
    end
  end
end
