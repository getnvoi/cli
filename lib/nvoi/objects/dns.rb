# frozen_string_literal: true

module Nvoi
  module Objects
    # DNS-related structs
    module Dns
      # Zone represents a Cloudflare DNS zone
      Zone = Struct.new(:id, :name, keyword_init: true)

      # Record represents a Cloudflare DNS record
      Record = Struct.new(:id, :type, :name, :content, :proxied, :ttl, keyword_init: true)
    end
  end
end
