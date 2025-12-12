# frozen_string_literal: true

module Nvoi
  module ConfigApi
    module Actions
      class SetDomainProvider < Base
        PROVIDERS = %w[cloudflare].freeze

        protected

        def mutate(data, provider:, **opts)
          raise ArgumentError, "provider is required" if provider.nil? || provider.to_s.empty?
          raise ArgumentError, "provider must be one of: #{PROVIDERS.join(', ')}" unless PROVIDERS.include?(provider.to_s)

          app(data)["domain_provider"] = { provider.to_s => build_config(provider.to_s, opts) }
        end

        private

        def build_config(provider, opts)
          case provider
          when "cloudflare"
            {
              "api_token" => opts[:api_token],
              "account_id" => opts[:account_id]
            }.compact
          end
        end
      end

      class DeleteDomainProvider < Base
        protected

        def mutate(data, **)
          app(data)["domain_provider"] = {}
        end
      end
    end
  end
end
