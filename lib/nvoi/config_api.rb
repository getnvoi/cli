# frozen_string_literal: true

module Nvoi
  module ConfigApi
    class << self
      # Init (creates new config - special case, handles crypto)
      def init(**args)
        Actions::Init.new.call(**args)
      end

      # Domain Provider
      def set_domain_provider(data, **args)
        Actions::SetDomainProvider.new(data).call(**args)
      end

      def delete_domain_provider(data)
        Actions::DeleteDomainProvider.new(data).call
      end

      # Compute Provider
      def set_compute_provider(data, **args)
        Actions::SetComputeProvider.new(data).call(**args)
      end

      def delete_compute_provider(data)
        Actions::DeleteComputeProvider.new(data).call
      end

      # Server
      def set_server(data, **args)
        Actions::SetServer.new(data).call(**args)
      end

      def delete_server(data, **args)
        Actions::DeleteServer.new(data).call(**args)
      end

      # Volume
      def set_volume(data, **args)
        Actions::SetVolume.new(data).call(**args)
      end

      def delete_volume(data, **args)
        Actions::DeleteVolume.new(data).call(**args)
      end

      # App
      def set_app(data, **args)
        Actions::SetApp.new(data).call(**args)
      end

      def delete_app(data, **args)
        Actions::DeleteApp.new(data).call(**args)
      end

      # Database
      def set_database(data, **args)
        Actions::SetDatabase.new(data).call(**args)
      end

      def delete_database(data)
        Actions::DeleteDatabase.new(data).call
      end

      # Secret
      def set_secret(data, **args)
        Actions::SetSecret.new(data).call(**args)
      end

      def delete_secret(data, **args)
        Actions::DeleteSecret.new(data).call(**args)
      end

      # Env
      def set_env(data, **args)
        Actions::SetEnv.new(data).call(**args)
      end

      def delete_env(data, **args)
        Actions::DeleteEnv.new(data).call(**args)
      end

      # Service
      def set_service(data, **args)
        Actions::SetService.new(data).call(**args)
      end

      def delete_service(data, **args)
        Actions::DeleteService.new(data).call(**args)
      end
    end
  end
end
