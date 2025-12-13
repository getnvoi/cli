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
require "minitest/reporters"
Minitest::Reporters.use!(Minitest::Reporters::SpecReporter.new)

require "nvoi"

# Silence logger in tests
Nvoi.logger = Nvoi::Utils::Logger.new(output: StringIO.new)

# Load CLI (ignored by Zeitwerk for lazy loading in production)
require_relative "../lib/nvoi/cli"

# Load all CLI commands for testing
Dir[File.expand_path("../lib/nvoi/cli/**/*.rb", __dir__)].sort.each { |f| require f }

# Stub Retry.poll to skip sleep in tests
module Nvoi
  module Utils
    module Retry
      class << self
        alias_method :poll_original, :poll

        def poll(max_attempts: 30, interval: 2, &block)
          poll_original(max_attempts:, interval: 0, &block)
        end
      end
    end
  end
end
