# frozen_string_literal: true

module Nvoi
  class Cli
    module Onboard
      module Steps
        # Collects environment variables and secrets
        class Env
          include UI

          ACTIONS = [
            { name: "Add variable", value: :add },
            { name: "Add secret (masked)", value: :secret },
            { name: "Done", value: :done }
          ].freeze

          def initialize(prompt, test_mode: false)
            @prompt = prompt
            @test_mode = test_mode
          end

          # Returns [env, secrets] tuple
          def call(existing_env: nil, existing_secrets: nil)
            section "Environment Variables"

            env = (existing_env || {}).dup
            secrets = (existing_secrets || {}).dup

            # Add default
            env["RAILS_ENV"] ||= "production"

            loop do
              show_table(env, secrets) unless env.empty? && secrets.empty?

              case @prompt.select("Action:", ACTIONS)
              when :add
                key = @prompt.ask("Variable name:") { |q| q.required true }
                value = @prompt.ask("Value:") { |q| q.required true }
                env[key] = value

              when :secret
                key = @prompt.ask("Secret name:") { |q| q.required true }
                value = @prompt.mask("Value:") { |q| q.required true }
                secrets[key] = value

              when :done
                break
              end
            end

            [env, secrets]
          end

          private

          def show_table(env, secrets)
            rows = []
            env.each { |k, v| rows << [k, v] }
            secrets.each { |k, _| rows << [k, "********"] }

            table(rows:, header: %w[Key Value])
          end
        end
      end
    end
  end
end
