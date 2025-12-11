# frozen_string_literal: true

require "yaml"
require "json"
require "openssl"
require "securerandom"
require "fileutils"
require "tempfile"
require "open3"
require "faraday"

require_relative "nvoi/version"

# Utils
require_relative "nvoi/utils/constants"
require_relative "nvoi/utils/errors"
require_relative "nvoi/utils/logger"
require_relative "nvoi/utils/crypto"
require_relative "nvoi/utils/retry"
require_relative "nvoi/utils/namer"
require_relative "nvoi/utils/env_resolver"
require_relative "nvoi/utils/templates"

# Objects
require_relative "nvoi/objects/server"
require_relative "nvoi/objects/network"
require_relative "nvoi/objects/firewall"
require_relative "nvoi/objects/volume"
require_relative "nvoi/objects/tunnel"
require_relative "nvoi/objects/dns"
require_relative "nvoi/objects/database"
require_relative "nvoi/objects/service_spec"
require_relative "nvoi/objects/config_override"

# External
require_relative "nvoi/external/cloud/base"
require_relative "nvoi/external/cloud/hetzner"
require_relative "nvoi/external/cloud/aws"
require_relative "nvoi/external/cloud/scaleway"
require_relative "nvoi/external/cloud/factory"

require_relative "nvoi/external/dns/cloudflare"

require_relative "nvoi/external/ssh"
require_relative "nvoi/external/kubectl"
require_relative "nvoi/external/containerd"

require_relative "nvoi/external/database/provider"
require_relative "nvoi/external/database/postgres"
require_relative "nvoi/external/database/mysql"
require_relative "nvoi/external/database/sqlite"

# CLI (Thor routing only - commands are lazy-loaded)
require_relative "nvoi/cli"

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
