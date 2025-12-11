# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "json"

# Load objects individually (no nvoi.rb yet)
Dir[File.expand_path("../lib/nvoi/objects/*.rb", __dir__)].each { |f| require f }
