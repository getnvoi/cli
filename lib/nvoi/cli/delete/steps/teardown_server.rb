# frozen_string_literal: true

module Nvoi
  class Cli
    module Delete
      module Steps
        # TeardownServer handles server deletion
        class TeardownServer
          def initialize(config, provider, log)
            @config = config
            @provider = provider
            @log = log
            @namer = config.namer
          end

          def run
            servers = @config.deploy.application.servers
            return if servers.empty?

            servers.each do |group_name, group_config|
              next unless group_config

              count = group_config.count.positive? ? group_config.count : 1
              @log.info "Deleting %d server(s) from group '%s'", count, group_name

              (1..count).each do |i|
                server_name = @namer.server_name(group_name, i)
                delete_server(server_name)
              end
            end
          end

          private

            def delete_server(server_name)
              @log.info "Deleting server: %s", server_name

              server = @provider.find_server(server_name)
              if server
                @provider.delete_server(server.id)
                @log.success "Server deleted: %s", server_name
              end
            rescue StandardError => e
              @log.warning "Failed to delete server %s: %s", server_name, e.message
            end
        end
      end
    end
  end
end
