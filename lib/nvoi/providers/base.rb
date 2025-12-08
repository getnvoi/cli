# frozen_string_literal: true

module Nvoi
  module Providers
    # Network represents a virtual network
    Network = Struct.new(:id, :name, :ip_range, keyword_init: true)

    # Firewall represents a firewall configuration
    Firewall = Struct.new(:id, :name, keyword_init: true)

    # Server represents a compute server/instance
    Server = Struct.new(:id, :name, :status, :public_ipv4, keyword_init: true)

    # Volume represents a block storage volume
    Volume = Struct.new(:id, :name, :size, :location, :status, :server_id, :device_path, keyword_init: true)

    # ServerCreateOptions contains options for creating a server
    ServerCreateOptions = Struct.new(:name, :type, :image, :location, :user_data, :network_id, :firewall_id, keyword_init: true)

    # VolumeCreateOptions contains options for creating a volume
    VolumeCreateOptions = Struct.new(:name, :size, :server_id, keyword_init: true)

    # Base provider interface - all providers must implement these methods
    class Base
      # Network operations
      def find_or_create_network(name)
        raise NotImplementedError
      end

      def get_network_by_name(name)
        raise NotImplementedError
      end

      def delete_network(id)
        raise NotImplementedError
      end

      # Firewall operations
      def find_or_create_firewall(name)
        raise NotImplementedError
      end

      def get_firewall_by_name(name)
        raise NotImplementedError
      end

      def delete_firewall(id)
        raise NotImplementedError
      end

      # Server operations
      def find_server(name)
        raise NotImplementedError
      end

      def list_servers
        raise NotImplementedError
      end

      def create_server(opts)
        raise NotImplementedError
      end

      def wait_for_server(server_id, max_attempts)
        raise NotImplementedError
      end

      def delete_server(id)
        raise NotImplementedError
      end

      # Volume operations
      def create_volume(opts)
        raise NotImplementedError
      end

      def get_volume(id)
        raise NotImplementedError
      end

      def get_volume_by_name(name)
        raise NotImplementedError
      end

      def delete_volume(id)
        raise NotImplementedError
      end

      def attach_volume(volume_id, server_id)
        raise NotImplementedError
      end

      def detach_volume(volume_id)
        raise NotImplementedError
      end

      # Validation operations
      def validate_instance_type(instance_type)
        raise NotImplementedError
      end

      def validate_region(region)
        raise NotImplementedError
      end

      def validate_credentials
        raise NotImplementedError
      end
    end
  end
end
