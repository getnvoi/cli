# frozen_string_literal: true

module Nvoi
  module Constants
    # Default deployment configuration file
    DEFAULT_CONFIG_FILE = "deploy.enc"

    # Network configuration
    NETWORK_CIDR = "10.0.0.0/16"
    SUBNET_CIDR = "10.0.1.0/24"

    # Server configuration
    DEFAULT_IMAGE = "ubuntu-24.04"
    SERVER_READY_INTERVAL = 10 # seconds
    SERVER_READY_MAX_ATTEMPTS = 60
    SSH_READY_INTERVAL = 5 # seconds
    SSH_READY_MAX_ATTEMPTS = 60

    # Deployment configuration
    MAX_DEPLOYMENT_RETRIES = 3
    STALE_DEPLOYMENT_LOCK_AGE = 3600 # 1 hour in seconds
    KEEP_COUNT_DEFAULT = 3

    # K3s configuration
    DEFAULT_K3S_VERSION = "v1.28.5+k3s1"

    # Registry configuration
    REGISTRY_PORT = 30500
    REGISTRY_NAME = "nvoi-registry"

    # Cloudflare
    CLOUDFLARE_API_BASE = "https://api.cloudflare.com/client/v4"
    TUNNEL_CONFIG_VERIFY_ATTEMPTS = 10

    # Traffic verification
    TRAFFIC_VERIFY_ATTEMPTS = 10
    TRAFFIC_VERIFY_CONSECUTIVE = 3
    TRAFFIC_VERIFY_INTERVAL = 5 # seconds

    # Paths
    DEPLOYMENT_LOCK_FILE = "/tmp/nvoi-deployment.lock"
    APP_BASE_DIR = "/opt/nvoi"

    # Database defaults
    DATABASE_PORTS = {
      "postgresql" => 5432,
      "postgres" => 5432,
      "mysql" => 3306,
      "redis" => 6379
    }.freeze

    # Default database images
    DATABASE_IMAGES = {
      "postgresql" => "postgres:15-alpine",
      "postgres" => "postgres:15-alpine",
      "mysql" => "mysql:8.0"
    }.freeze
  end
end
