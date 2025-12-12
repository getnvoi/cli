# frozen_string_literal: true

module Nvoi
  module ConfigApi
    module Actions
      class SetComputeProvider < Base
        PROVIDERS = %w[hetzner aws scaleway].freeze

        protected

        def mutate(data, provider:, **opts)
          raise ArgumentError, "provider is required" if provider.nil? || provider.to_s.empty?
          raise ArgumentError, "provider must be one of: #{PROVIDERS.join(', ')}" unless PROVIDERS.include?(provider.to_s)

          app(data)["compute_provider"] = { provider.to_s => build_config(provider.to_s, opts) }
        end

        private

        def build_config(provider, opts)
          case provider
          when "hetzner"
            {
              "api_token" => opts[:api_token],
              "server_type" => opts[:server_type],
              "server_location" => opts[:server_location]
            }.compact
          when "aws"
            {
              "access_key_id" => opts[:access_key_id],
              "secret_access_key" => opts[:secret_access_key],
              "region" => opts[:region],
              "instance_type" => opts[:instance_type]
            }.compact
          when "scaleway"
            {
              "secret_key" => opts[:secret_key],
              "project_id" => opts[:project_id],
              "zone" => opts[:zone],
              "server_type" => opts[:server_type]
            }.compact
          end
        end
      end

      class DeleteComputeProvider < Base
        protected

        def mutate(data, **)
          app(data)["compute_provider"] = {}
        end
      end
    end
  end
end
