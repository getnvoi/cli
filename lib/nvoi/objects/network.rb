# frozen_string_literal: true

module Nvoi
  module Objects
    # Network-related structs
    module Network
      # Record represents a virtual network
      Record = Struct.new(:id, :name, :ip_range, keyword_init: true)
    end
  end
end
