# frozen_string_literal: true

module Nvoi
  module Configuration
    # ServerVolume defines a volume attached to a server
    class ServerVolume
      attr_accessor :size

      def initialize(data = {})
        raise ArgumentError, "volume config must be a hash with 'size' key" unless data.is_a?(Hash)

        @size = data["size"]&.to_i || 10
      end
    end

    # Server contains server instance configuration
    class Server
      attr_accessor :master, :type, :location, :count, :volumes

      def initialize(data = {})
        @master = data["master"] || false
        @type = data["type"]
        @location = data["location"]
        @count = data["count"]&.to_i || 1
        @volumes = (data["volumes"] || {}).transform_values { |v| ServerVolume.new(v || {}) }
      end

      def master?
        @master == true
      end

      def volume(name)
        @volumes[name.to_s]
      end
    end
  end
end
