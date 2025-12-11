# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "json"

# Load errors first (needed by other modules)
require_relative "../lib/nvoi/utils/errors"

# Load objects
Dir[File.expand_path("../lib/nvoi/objects/*.rb", __dir__)].each { |f| require f }

# Load utils
Dir[File.expand_path("../lib/nvoi/utils/*.rb", __dir__)].each { |f| require f }
