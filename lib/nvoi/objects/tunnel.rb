# frozen_string_literal: true

module Nvoi
  module Objects
    # Tunnel represents a Cloudflare tunnel
    Tunnel = Struct.new(:id, :name, :token, keyword_init: true)

    # TunnelInfo holds information about a configured tunnel
    TunnelInfo = Struct.new(:service_name, :hostname, :tunnel_id, :tunnel_token, :port, keyword_init: true)
  end
end
