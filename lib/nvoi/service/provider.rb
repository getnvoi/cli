# frozen_string_literal: true

module Nvoi
  module Service
    # Provider initialization helpers
    module ProviderHelper
      def init_provider(config)
        case config.provider_name
        when "hetzner"
          h = config.hetzner
          Providers::Hetzner.new(h.api_token)
        when "aws"
          a = config.aws
          Providers::AWS.new(a.access_key_id, a.secret_access_key, a.region)
        else
          raise ProviderError, "unknown provider: #{config.provider_name}"
        end
      end

      def validate_provider_config(config, provider)
        case config.provider_name
        when "hetzner"
          h = config.hetzner
          provider.validate_credentials
          provider.validate_instance_type(h.server_type)
          provider.validate_region(h.server_location)
        when "aws"
          a = config.aws
          provider.validate_credentials
          provider.validate_instance_type(a.instance_type)
          provider.validate_region(a.region)
        end
      end
    end
  end
end
