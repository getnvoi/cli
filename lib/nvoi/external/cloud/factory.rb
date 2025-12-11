# frozen_string_literal: true

module Nvoi
  module External
    module Cloud
      # Factory creates cloud providers from config
      module Factory
        class << self
          def for(config)
            case config.provider_name
            when "hetzner"
              h = config.hetzner
              Hetzner.new(h.api_token)
            when "aws"
              a = config.aws
              AWS.new(a.access_key_id, a.secret_access_key, a.region)
            when "scaleway"
              s = config.scaleway
              Scaleway.new(s.secret_key, s.project_id, zone: s.zone)
            else
              raise ProviderError, "unknown provider: #{config.provider_name}"
            end
          end

          def validate(config, provider)
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
            when "scaleway"
              s = config.scaleway
              provider.validate_credentials
              provider.validate_instance_type(s.server_type)
              provider.validate_region(s.zone)
            end
          end
        end
      end
    end
  end
end
