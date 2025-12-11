# frozen_string_literal: true

module Nvoi
  module Objects
    # Server represents a compute server/instance
    Server = Struct.new(:id, :name, :status, :public_ipv4, keyword_init: true)

    # ServerCreateOptions contains options for creating a server
    ServerCreateOptions = Struct.new(:name, :type, :image, :location, :user_data, :network_id, :firewall_id, keyword_init: true)
  end
end
