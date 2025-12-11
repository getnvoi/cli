# frozen_string_literal: true

module Nvoi
  module Objects
    # Network represents a virtual network
    Network = Struct.new(:id, :name, :ip_range, keyword_init: true)
  end
end
