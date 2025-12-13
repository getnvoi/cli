# frozen_string_literal: true

module Nvoi
  module Configuration
    # Result wrapper for Builder operations
    class Result
      attr_reader :data, :error_type, :error_message

      def initialize(data: nil, error_type: nil, error_message: nil)
        @data = data
        @error_type = error_type
        @error_message = error_message
      end

      def success? = @error_type.nil?
      def failure? = !success?

      def self.success(data)
        new(data:)
      end

      def self.failure(type, message)
        new(error_type: type, error_message: message)
      end

      # Result for init operations (includes encryption artifacts)
      class Init
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
