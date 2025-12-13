# frozen_string_literal: true

module Nvoi
  module External
    module Dns
      module Types
        # Zone represents a Cloudflare DNS zone
        Zone = Struct.new(:id, :name, keyword_init: true)

        # Record represents a Cloudflare DNS record
        Record = Struct.new(:id, :type, :name, :content, :proxied, :ttl, keyword_init: true)

        # Tunnel-related structs (Cloudflare tunnels)
        module Tunnel
          # Record represents a Cloudflare tunnel
          Record = Struct.new(:id, :name, :token, keyword_init: true)

          # Info holds information about a configured tunnel
          Info = Struct.new(:service_name, :hostname, :tunnel_id, :tunnel_token, :port, keyword_init: true)
        end
      end
    end
  end
end
