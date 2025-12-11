# frozen_string_literal: true

require "test_helper"

class RetryPollTest < Minitest::Test
  def test_poll_returns_truthy_value_immediately
    call_count = 0
    result = Nvoi::Utils::Retry.poll(max_attempts: 5, interval: 0.01) do
      call_count += 1
      "found"
    end

    assert_equal "found", result
    assert_equal 1, call_count
  end

  def test_poll_retries_on_falsy_value
    call_count = 0
    result = Nvoi::Utils::Retry.poll(max_attempts: 5, interval: 0.01) do
      call_count += 1
      call_count >= 3 ? "found" : nil
    end

    assert_equal "found", result
    assert_equal 3, call_count
  end

  def test_poll_returns_nil_after_max_attempts
    call_count = 0
    result = Nvoi::Utils::Retry.poll(max_attempts: 3, interval: 0.01) do
      call_count += 1
      nil
    end

    assert_nil result
    assert_equal 3, call_count
  end

  def test_poll_returns_false_as_falsy
    call_count = 0
    result = Nvoi::Utils::Retry.poll(max_attempts: 3, interval: 0.01) do
      call_count += 1
      false
    end

    assert_nil result
    assert_equal 3, call_count
  end

  def test_poll_bang_raises_on_timeout
    assert_raises(Nvoi::Errors::TimeoutError) do
      Nvoi::Utils::Retry.poll!(max_attempts: 2, interval: 0.01, error_message: "custom error") do
        nil
      end
    end
  end

  def test_poll_bang_returns_result_on_success
    result = Nvoi::Utils::Retry.poll!(max_attempts: 3, interval: 0.01) do
      "success"
    end

    assert_equal "success", result
  end
end
