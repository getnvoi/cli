# frozen_string_literal: true

module Nvoi
  module Objects
    # Tunnel-related structs
    module Tunnel
      # Record represents a Cloudflare tunnel
      Record = Struct.new(:id, :name, :token, keyword_init: true)

      # Info holds information about a configured tunnel
      Info = Struct.new(:service_name, :hostname, :tunnel_id, :tunnel_token, :port, keyword_init: true)
    end
  end
end
