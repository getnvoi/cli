# frozen_string_literal: true

require "pastel"
require "tty-spinner"
require "tty-table"
require "tty-box"

module Nvoi
  class Cli
    module Onboard
      # Shared UI helpers for onboard steps
      module Ui
        MAX_RETRIES = 3

        def section(title)
          output.puts
          output.puts pastel.bold("─── #{title} ───")
        end

        def success(msg)
          output.puts "#{pastel.green("✓")} #{msg}"
        end

        def error(msg)
          output.puts "#{pastel.red("✗")} #{msg}"
        end

        def with_spinner(message)
          return yield if @test_mode

          spinner = TTY::Spinner.new("[:spinner] #{message}", format: :dots)
          spinner.auto_spin
          begin
            result = yield
            spinner.success("done")
            result
          rescue StandardError => e
            spinner.error("failed")
            raise
          end
        end

        def prompt_with_retry(message, mask: false, max: MAX_RETRIES)
          retries = 0
          loop do
            value = mask ? @prompt.mask(message) : @prompt.ask(message) { |q| q.required true }
            begin
              yield(value) if block_given?
              return value
            rescue Errors::ValidationError, Errors::AuthenticationError => e
              retries += 1
              if retries >= max
                error("Failed after #{max} attempts: #{e.message}")
                raise
              end
              output.puts("#{e.message}. Please try again. (#{retries}/#{max})")
            end
          end
        end

        def table(rows:, header: nil)
          t = TTY::Table.new(header:, rows:)
          output.puts t.render(:unicode, padding: [0, 1])
          output.puts
        end

        def box(text)
          output.puts TTY::Box.frame(text, padding: [0, 2], align: :center, border: :light)
          output.puts
        end

        def output
          @prompt.output
        end

        private

          def pastel
            @pastel ||= Pastel.new
          end
      end
    end
  end
end
