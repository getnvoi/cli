# frozen_string_literal: true

module Nvoi
  module Configuration
    module Providers
      # DomainProvider contains domain provider configuration
      class DomainProvider
        attr_accessor :cloudflare

        def initialize(data = nil)
          data ||= {}
          @cloudflare = data["cloudflare"] ? Cloudflare.new(data["cloudflare"]) : nil
        end
      end

      # ComputeProvider contains compute provider configuration
      class ComputeProvider
        attr_accessor :hetzner, :aws, :scaleway

        def initialize(data = nil)
          data ||= {}
          @hetzner = data["hetzner"] ? Hetzner.new(data["hetzner"]) : nil
          @aws = data["aws"] ? AwsCfg.new(data["aws"]) : nil
          @scaleway = data["scaleway"] ? Scaleway.new(data["scaleway"]) : nil
        end
      end

      # Cloudflare contains Cloudflare-specific configuration
      class Cloudflare
        attr_accessor :api_token, :account_id

        def initialize(data = nil)
          data ||= {}
          @api_token = data["api_token"]
          @account_id = data["account_id"]
        end
      end

      # Hetzner contains Hetzner-specific configuration
      class Hetzner
        attr_accessor :api_token, :server_type, :server_location, :architecture

        def initialize(data = nil)
          data ||= {}
          @api_token = data["api_token"]
          @server_type = data["server_type"]
          @server_location = data["server_location"]
          @architecture = data["architecture"]
        end
      end

      # AwsCfg contains AWS-specific configuration
      class AwsCfg
        attr_accessor :access_key_id, :secret_access_key, :region, :instance_type, :architecture

        def initialize(data = nil)
          data ||= {}
          @access_key_id = data["access_key_id"]
          @secret_access_key = data["secret_access_key"]
          @region = data["region"]
          @instance_type = data["instance_type"]
          @architecture = data["architecture"]
        end
      end

      # Scaleway contains Scaleway-specific configuration
      class Scaleway
        attr_accessor :secret_key, :project_id, :zone, :server_type, :architecture

        def initialize(data = nil)
          data ||= {}
          @secret_key = data["secret_key"]
          @project_id = data["project_id"]
          @zone = data["zone"] || "fr-par-1"
          @server_type = data["server_type"]
          @architecture = data["architecture"]
        end
      end
    end
  end
end
