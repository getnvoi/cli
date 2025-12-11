# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/test/"
  add_group "Objects", "lib/nvoi/objects"
  add_group "Utils", "lib/nvoi/utils"
  add_group "External", "lib/nvoi/external"
  add_group "CLI", "lib/nvoi/cli"
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "json"

# Load errors first (needed by other modules)
require_relative "../lib/nvoi/utils/errors"

# Load objects
Dir[File.expand_path("../lib/nvoi/objects/*.rb", __dir__)].each { |f| require f }

# Load utils
Dir[File.expand_path("../lib/nvoi/utils/*.rb", __dir__)].each { |f| require f }
