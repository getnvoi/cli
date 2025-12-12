# frozen_string_literal: true

module Nvoi
  module ConfigApi
    class << self
      # Compute Provider
      def set_compute_provider(config, key, **args)
        Actions::SetComputeProvider.new(config, key).call(**args)
      end

      def delete_compute_provider(config, key)
        Actions::DeleteComputeProvider.new(config, key).call
      end

      # Server
      def set_server(config, key, **args)
        Actions::SetServer.new(config, key).call(**args)
      end

      def delete_server(config, key, **args)
        Actions::DeleteServer.new(config, key).call(**args)
      end

      # Volume
      def set_volume(config, key, **args)
        Actions::SetVolume.new(config, key).call(**args)
      end

      def delete_volume(config, key, **args)
        Actions::DeleteVolume.new(config, key).call(**args)
      end

      # App
      def set_app(config, key, **args)
        Actions::SetApp.new(config, key).call(**args)
      end

      def delete_app(config, key, **args)
        Actions::DeleteApp.new(config, key).call(**args)
      end

      # Database
      def set_database(config, key, **args)
        Actions::SetDatabase.new(config, key).call(**args)
      end

      def delete_database(config, key)
        Actions::DeleteDatabase.new(config, key).call
      end

      # Secret
      def set_secret(config, key, **args)
        Actions::SetSecret.new(config, key).call(**args)
      end

      def delete_secret(config, key, **args)
        Actions::DeleteSecret.new(config, key).call(**args)
      end

      # Env
      def set_env(config, key, **args)
        Actions::SetEnv.new(config, key).call(**args)
      end

      def delete_env(config, key, **args)
        Actions::DeleteEnv.new(config, key).call(**args)
      end
    end
  end
end
