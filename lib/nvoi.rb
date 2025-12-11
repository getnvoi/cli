# frozen_string_literal: true

module Nvoi
  class Error < StandardError; end
end

require "zeitwerk"
require "yaml"
require "json"
require "openssl"
require "securerandom"
require "fileutils"
require "tempfile"
require "open3"
require "faraday"

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/nvoi/cli")  # CLI commands are lazy-loaded
loader.setup

module Nvoi
  class << self
    attr_accessor :logger

    def root
      File.expand_path("..", __dir__)
    end

    def templates_path
      File.join(root, "templates")
    end
  end

  self.logger = Utils::Logger.new
end
