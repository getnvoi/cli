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
loader.ignore("#{__dir__}/nvoi/config_api")  # ConfigApi uses non-standard naming
loader.setup

# Load ConfigApi manually (uses non-standard naming convention)
require_relative "nvoi/config_api/result"
require_relative "nvoi/config_api/base"
require_relative "nvoi/config_api/actions/init"
require_relative "nvoi/config_api/actions/domain_provider"
require_relative "nvoi/config_api/actions/compute_provider"
require_relative "nvoi/config_api/actions/server"
require_relative "nvoi/config_api/actions/volume"
require_relative "nvoi/config_api/actions/app"
require_relative "nvoi/config_api/actions/database"
require_relative "nvoi/config_api/actions/secret"
require_relative "nvoi/config_api/actions/env"
require_relative "nvoi/config_api/actions/service"
require_relative "nvoi/config_api"

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
