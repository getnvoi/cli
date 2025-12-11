# frozen_string_literal: true

module Nvoi
  module Objects
    # Server-related structs
    module Server
      # Record represents a compute server/instance
      Record = Struct.new(:id, :name, :status, :public_ipv4, :private_ipv4, keyword_init: true)

      # CreateOptions contains options for creating a server
      CreateOptions = Struct.new(:name, :type, :image, :location, :user_data, :network_id, :firewall_id, :ssh_keys, keyword_init: true)
    end
  end
end
