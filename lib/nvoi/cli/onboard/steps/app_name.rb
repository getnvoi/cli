# frozen_string_literal: true

module Nvoi
  class Cli
    module Onboard
      module Steps
        # Collects application name
        class AppName
          include UI

          def initialize(prompt, test_mode: false)
            @prompt = prompt
            @test_mode = test_mode
          end

          def call(existing: nil)
            @prompt.ask("Application name:", default: existing) do |q|
              q.required true
              q.validate(/\A[a-z0-9_-]+\z/i, "Only letters, numbers, dashes, underscores")
            end
          end
        end
      end
    end
  end
end
