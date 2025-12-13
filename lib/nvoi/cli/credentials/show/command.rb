# frozen_string_literal: true

module Nvoi
  class Cli
    module Credentials
      module Show
        # Command handles displaying decrypted credentials
        class Command
          def initialize(options)
            @options = options
          end

          def run
            working_dir = resolve_working_dir
            manager = Utils::CredentialStore.new(working_dir, @options[:credentials], @options[:master_key])

            content = manager.read
            puts content
          end

          private

            def resolve_working_dir
              wd = @options[:dir]
              if wd.blank? || wd == "."
                Dir.pwd
              else
                File.expand_path(wd)
              end
            end
        end
      end
    end
  end
end
