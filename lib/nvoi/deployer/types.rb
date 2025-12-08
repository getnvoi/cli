# frozen_string_literal: true

module Nvoi
  module Deployer
    # TunnelInfo holds information about a configured tunnel
    TunnelInfo = Struct.new(:service_name, :hostname, :tunnel_id, :tunnel_token, :port, keyword_init: true)
  end
end
