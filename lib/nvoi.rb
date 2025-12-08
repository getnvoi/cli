# frozen_string_literal: true

require "yaml"
require "json"
require "openssl"
require "securerandom"
require "fileutils"
require "tempfile"
require "open3"

require_relative "nvoi/version"
require_relative "nvoi/constants"
require_relative "nvoi/errors"
require_relative "nvoi/logger"

require_relative "nvoi/config/types"
require_relative "nvoi/config/naming"
require_relative "nvoi/config/ssh_keys"
require_relative "nvoi/config/env_resolver"
require_relative "nvoi/config/loader"
require_relative "nvoi/config/config"

require_relative "nvoi/credentials/crypto"
require_relative "nvoi/credentials/manager"
require_relative "nvoi/credentials/editor"

require_relative "nvoi/providers/base"
require_relative "nvoi/providers/hetzner"
require_relative "nvoi/providers/aws"

require_relative "nvoi/cloudflare/client"

require_relative "nvoi/remote/ssh_executor"
require_relative "nvoi/remote/docker_manager"
require_relative "nvoi/remote/volume_manager"

require_relative "nvoi/k8s/templates"
require_relative "nvoi/k8s/renderer"

require_relative "nvoi/deployer/types"
require_relative "nvoi/deployer/retry"
require_relative "nvoi/deployer/tunnel_manager"
require_relative "nvoi/deployer/infrastructure"
require_relative "nvoi/deployer/image_builder"
require_relative "nvoi/deployer/service_deployer"
require_relative "nvoi/deployer/cleaner"
require_relative "nvoi/deployer/orchestrator"

require_relative "nvoi/steps/server_provisioner"
require_relative "nvoi/steps/volume_provisioner"
require_relative "nvoi/steps/k3s_provisioner"
require_relative "nvoi/steps/k3s_cluster_setup"
require_relative "nvoi/steps/tunnel_configurator"
require_relative "nvoi/steps/database_provisioner"
require_relative "nvoi/steps/services_provisioner"
require_relative "nvoi/steps/application_deployer"

require_relative "nvoi/service/provider"
require_relative "nvoi/service/deploy"
require_relative "nvoi/service/delete"
require_relative "nvoi/service/exec"

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

  self.logger = Logger.new
end
