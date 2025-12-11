# frozen_string_literal: true

module Nvoi
  module Utils
    # StepExecutor executes deployment steps with automatic retry on transient failures
    class StepExecutor
      def initialize(max_retries, log)
        @max_retries = max_retries
        @log = log
      end

      # Execute runs a step with automatic retry on retryable errors
      def execute(step_name)
        last_error = nil

        @max_retries.times do |attempt|
          @log.info "Retry attempt %d/%d for: %s", attempt, @max_retries - 1, step_name if attempt > 0

          begin
            yield
            return # Success
          rescue StandardError => e
            last_error = e

            # Check if error is retryable
            unless retryable?(e)
              @log.error "Non-retryable error in %s: %s", step_name, e.message
              raise e
            end

            # Log retry with backoff
            if attempt < @max_retries - 1
              backoff_duration = exponential_backoff(attempt)
              @log.warning "Retryable error in %s: %s (backing off %ds)", step_name, e.message, backoff_duration
              sleep(backoff_duration)
            end
          end
        end

        raise Errors::DeploymentError.new(step_name, "max retries (#{@max_retries}) exceeded: #{last_error&.message}")
      end

      private

        # Exponential backoff: attempt 0: 1s, attempt 1: 2s, attempt 2: 4s, etc.
        def exponential_backoff(attempt)
          2**attempt
        end

        # Check if an error is retryable
        def retryable?(error)
          return error.retryable? if error.respond_to?(:retryable?)

          # Default: network/SSH errors are retryable
          error.is_a?(SSHError) || error.is_a?(NetworkError)
        end
    end

    # Retry helper module for simple retry scenarios
    module Retry
      def self.with_retry(max_attempts: 3, log: nil)
        executor = StepExecutor.new(max_attempts, log)
        executor.execute("operation") { yield }
      end
    end
  end
end
