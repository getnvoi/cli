# frozen_string_literal: true

module Nvoi
  module ConfigApi
    class Result
      attr_reader :data, :error_type, :error_message

      def self.success(data)
        new(data: data)
      end

      def self.failure(type, message)
        new(error_type: type, error_message: message)
      end

      def initialize(data: nil, error_type: nil, error_message: nil)
        @data = data
        @error_type = error_type
        @error_message = error_message
      end

      def success? = @error_type.nil?
      def failure? = !success?
    end
  end
end
