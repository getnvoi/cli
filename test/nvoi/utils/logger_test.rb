# frozen_string_literal: true

require "test_helper"
require "stringio"

class LoggerTest < Minitest::Test
  def setup
    @output = StringIO.new
    @logger = Nvoi::Utils::Logger.new(output: @output, color: false)
  end

  def test_info_logs_message
    @logger.info("test message")
    assert_match(/\[INFO\] test message/, @output.string)
  end

  def test_success_logs_message
    @logger.success("deploy complete")
    assert_match(/\[SUCCESS\] deploy complete/, @output.string)
  end

  def test_warning_logs_message
    @logger.warning("disk space low")
    assert_match(/\[WARNING\] disk space low/, @output.string)
  end

  def test_error_logs_message
    @logger.error("connection failed")
    assert_match(/\[ERROR\] connection failed/, @output.string)
  end

  def test_debug_logs_only_when_env_set
    @logger.debug("debug info")
    assert_empty @output.string

    ENV["NVOI_DEBUG"] = "1"
    @logger.debug("debug info")
    assert_match(/\[DEBUG\] debug info/, @output.string)
  ensure
    ENV.delete("NVOI_DEBUG")
  end

  def test_format_message_with_args
    @logger.info("deploying %s to %s", "myapp", "production")
    assert_match(/deploying myapp to production/, @output.string)
  end

  def test_separator_outputs_dashes
    @logger.separator
    assert_match(/-{60}/, @output.string)
  end

  def test_blank_outputs_newline
    @logger.blank
    assert_equal "\n", @output.string
  end

  def test_timestamp_format
    @logger.info("test")
    assert_match(/\[\d{2}:\d{2}:\d{2}\]/, @output.string)
  end
end
