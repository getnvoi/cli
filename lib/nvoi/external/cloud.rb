# frozen_string_literal: true

module Nvoi
  module External
    module Cloud
      def self.for(config)
        Factory.for(config)
      end

      def self.validate(config, provider)
        Factory.validate(config, provider)
      end
    end
  end
end
