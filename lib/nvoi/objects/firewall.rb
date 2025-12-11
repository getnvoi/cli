# frozen_string_literal: true

module Nvoi
  module Objects
    # Firewall-related structs
    module Firewall
      # Record represents a firewall configuration
      Record = Struct.new(:id, :name, keyword_init: true)
    end
  end
end
