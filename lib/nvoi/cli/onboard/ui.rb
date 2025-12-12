# frozen_string_literal: true

require "pastel"
require "tty-spinner"
require "tty-table"
require "tty-box"

module Nvoi
  class Cli
    module Onboard
      # Shared UI helpers for onboard steps
      module UI
        MAX_RETRIES = 3

        def section(title)
          puts
          puts pastel.bold("─── #{title} ───")
        end

        def success(msg)
          puts "#{pastel.green("✓")} #{msg}"
        end

        def error(msg)
          warn "#{pastel.red("✗")} #{msg}"
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
              warn("#{e.message}. Please try again. (#{retries}/#{max})")
            end
          end
        end

        def table(rows:, header: nil)
          t = TTY::Table.new(header:, rows:)
          puts t.render(:unicode, padding: [0, 1])
          puts
        end

        def box(text)
          puts TTY::Box.frame(text, padding: [0, 2], align: :center, border: :light)
          puts
        end

        private

        def pastel
          @pastel ||= Pastel.new
        end
      end
    end
  end
end
