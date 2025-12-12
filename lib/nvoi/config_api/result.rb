# frozen_string_literal: true

module Nvoi
  module ConfigApi
    class Result
      attr_reader :config, :error_type, :error_message

      def self.success(config)
        new(config: config)
      end

      def self.failure(type, message)
        new(error_type: type, error_message: message)
      end

      def initialize(config: nil, error_type: nil, error_message: nil)
        @config = config
        @error_type = error_type
        @error_message = error_message
      end

      def success? = @error_type.nil?
      def failure? = !success?
    end
  end
end
