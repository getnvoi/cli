# frozen_string_literal: true

module Nvoi
  module ConfigApi
    module Actions
      class Init
        def call(name:, environment: "production")
          raise ArgumentError, "name is required" if name.nil? || name.to_s.empty?

          # Generate master key
          master_key = Utils::Crypto.generate_key

          # Generate SSH keypair (reuse existing utility)
          private_key, public_key = Utils::ConfigLoader.generate_keypair

          # Build initial config
          config_data = {
            "application" => {
              "name" => name.to_s,
              "environment" => environment.to_s,
              "domain_provider" => {},
              "compute_provider" => {},
              "servers" => {},
              "app" => {},
              "services" => {},
              "env" => {},
              "secrets" => {},
              "ssh_keys" => {
                "private_key" => private_key,
                "public_key" => public_key
              }
            }
          }

          # Encrypt config
          yaml = YAML.dump(config_data)
          encrypted_config = Utils::Crypto.encrypt(yaml, master_key)

          InitResult.new(
            config: encrypted_config,
            master_key:,
            ssh_public_key: public_key
          )
        rescue ArgumentError => e
          InitResult.new(error_type: :invalid_args, error_message: e.message)
        rescue Errors::ConfigError => e
          InitResult.new(error_type: :config_error, error_message: e.message)
        end
      end

      class InitResult
        attr_reader :config, :master_key, :ssh_public_key, :error_type, :error_message

        def initialize(config: nil, master_key: nil, ssh_public_key: nil, error_type: nil, error_message: nil)
          @config = config
          @master_key = master_key
          @ssh_public_key = ssh_public_key
          @error_type = error_type
          @error_message = error_message
        end

        def success? = @error_type.nil?
        def failure? = !success?
      end
    end
  end
end
