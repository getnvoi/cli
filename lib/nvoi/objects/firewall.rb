# frozen_string_literal: true

module Nvoi
  module Objects
    # Firewall represents a firewall configuration
    Firewall = Struct.new(:id, :name, keyword_init: true)
  end
end
