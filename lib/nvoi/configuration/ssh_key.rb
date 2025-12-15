# frozen_string_literal: true

module Nvoi
  module Configuration
    # SshKey defines SSH key content (stored in encrypted config)
    class SshKey
      attr_accessor :private_key, :public_key

      def initialize(data = nil)
        data ||= {}
        @private_key = data["private_key"]
        @public_key = data["public_key"]
      end
    end
  end
end
