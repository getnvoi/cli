# frozen_string_literal: true

module Nvoi
  module Configuration
    # Deploy represents the root deployment configuration
    class Deploy
      attr_accessor :application

      def initialize(data = {})
        @application = Application.new(data["application"] || {})
      end
    end
  end
end
