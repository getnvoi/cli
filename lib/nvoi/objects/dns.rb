# frozen_string_literal: true

module Nvoi
  module Objects
    # Zone represents a Cloudflare DNS zone
    Zone = Struct.new(:id, :name, keyword_init: true)

    # DNSRecord represents a Cloudflare DNS record
    DNSRecord = Struct.new(:id, :type, :name, :content, :proxied, :ttl, keyword_init: true)
  end
end
