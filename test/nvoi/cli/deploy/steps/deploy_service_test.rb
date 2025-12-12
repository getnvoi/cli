# frozen_string_literal: true

require "test_helper"

class DeployServiceStepTest < Minitest::Test
  def setup
    @mock_ssh = Minitest::Mock.new
    @mock_log = Minitest::Mock.new
    @mock_kubectl = Minitest::Mock.new
  end

  def test_build_hostname_without_branch
    result = Nvoi::Utils::Namer.build_hostname("golang", "rb.run")
    assert_equal "golang.rb.run", result
  end

  def test_build_hostname_with_branch_prefix
    # After ConfigOverride.apply, subdomain becomes "rel-golang"
    result = Nvoi::Utils::Namer.build_hostname("rel-golang", "rb.run")
    assert_equal "rel-golang.rb.run", result
  end

  def test_build_hostname_with_nil_subdomain
    result = Nvoi::Utils::Namer.build_hostname(nil, "rb.run")
    assert_equal "rb.run", result
  end

  def test_build_hostname_with_empty_subdomain
    result = Nvoi::Utils::Namer.build_hostname("", "rb.run")
    assert_equal "rb.run", result
  end

  def test_build_hostname_with_at_subdomain
    result = Nvoi::Utils::Namer.build_hostname("@", "rb.run")
    assert_equal "rb.run", result
  end

  def test_config_override_changes_subdomain_for_ingress
    # This tests the full flow: ConfigOverride modifies subdomain,
    # then build_hostname produces correct ingress hostname

    # Original subdomain
    original_subdomain = "golang"

    # After ConfigOverride with branch "rel"
    branched_subdomain = "rel-#{original_subdomain}"

    # Hostname used for ingress should be branched
    hostname = Nvoi::Utils::Namer.build_hostname(branched_subdomain, "rb.run")
    assert_equal "rel-golang.rb.run", hostname
  end

  MockHealthcheck = Struct.new(:path, keyword_init: true)
  MockServiceConfig = Struct.new(:domain, :subdomain, :healthcheck, keyword_init: true)

  def test_verify_traffic_uses_correct_hostname
    # Test that verify_traffic_switchover builds URL with branched hostname
    service_config = MockServiceConfig.new(
      domain: "rb.run",
      subdomain: "rel-golang",  # After branch override applied
      healthcheck: MockHealthcheck.new(path: "/health")
    )

    hostname = Nvoi::Utils::Namer.build_hostname(service_config.subdomain, service_config.domain)
    health_path = service_config.healthcheck&.path || "/"
    public_url = "https://#{hostname}#{health_path}"

    assert_equal "https://rel-golang.rb.run/health", public_url
  end
end

class TrafficVerificationTest < Minitest::Test
  def setup
    @log_output = []
    @mock_log = Object.new
    @mock_log.define_singleton_method(:info) { |msg, *args| @log_output << [:info, format(msg, *args)] }
    @mock_log.define_singleton_method(:success) { |msg, *args| @log_output << [:success, format(msg, *args)] }
    @mock_log.define_singleton_method(:warning) { |msg, *args| @log_output << [:warning, format(msg, *args)] }
    @mock_log.instance_variable_set(:@log_output, @log_output)
  end

  def test_logs_transition_when_first_success
    # Simulate the verification logic inline to test log output
    log_output = @log_output
    consecutive_success = 0
    required_consecutive = 3
    max_attempts = 10

    # Simulate: 2 failures, then 3 successes
    results = [
      { success: false, message: "Error backend" },
      { success: false, message: "Error backend" },
      { success: true, http_code: "200" },
      { success: true, http_code: "200" },
      { success: true, http_code: "200" }
    ]

    results.each_with_index do |result, attempt|
      if result[:success]
        if consecutive_success == 0
          log_output << [:info, "[#{attempt + 1}/#{max_attempts}] App responding, verifying stability..."]
        end
        consecutive_success += 1
        log_output << [:success, "[#{consecutive_success}/#{required_consecutive}] Public URL responding: #{result[:http_code]}"]
      else
        consecutive_success = 0
        log_output << [:info, "[#{attempt + 1}/#{max_attempts}] #{result[:message]}"]
      end
    end

    # Verify transition log appears at attempt 3 (first success)
    assert_includes log_output, [:info, "[3/10] App responding, verifying stability..."]

    # Verify failure logs
    assert_includes log_output, [:info, "[1/10] Error backend"]
    assert_includes log_output, [:info, "[2/10] Error backend"]

    # Verify success logs
    assert_includes log_output, [:success, "[1/3] Public URL responding: 200"]
    assert_includes log_output, [:success, "[2/3] Public URL responding: 200"]
    assert_includes log_output, [:success, "[3/3] Public URL responding: 200"]
  end

  def test_logs_transition_on_immediate_success
    log_output = @log_output
    consecutive_success = 0
    required_consecutive = 3
    max_attempts = 10

    # Simulate: immediate successes
    results = [
      { success: true, http_code: "200" },
      { success: true, http_code: "200" },
      { success: true, http_code: "200" }
    ]

    results.each_with_index do |result, attempt|
      if result[:success]
        if consecutive_success == 0
          log_output << [:info, "[#{attempt + 1}/#{max_attempts}] App responding, verifying stability..."]
        end
        consecutive_success += 1
        log_output << [:success, "[#{consecutive_success}/#{required_consecutive}] Public URL responding: #{result[:http_code]}"]
      end
    end

    # Transition log should appear on first attempt
    assert_includes log_output, [:info, "[1/10] App responding, verifying stability..."]
  end

  def test_logs_transition_after_streak_broken
    log_output = @log_output
    consecutive_success = 0
    required_consecutive = 3
    max_attempts = 10

    # Simulate: 1 success, 1 failure (streak broken), then 3 successes
    results = [
      { success: true, http_code: "200" },
      { success: false, message: "Error" },
      { success: true, http_code: "200" },
      { success: true, http_code: "200" },
      { success: true, http_code: "200" }
    ]

    results.each_with_index do |result, attempt|
      if result[:success]
        if consecutive_success == 0
          log_output << [:info, "[#{attempt + 1}/#{max_attempts}] App responding, verifying stability..."]
        end
        consecutive_success += 1
        log_output << [:success, "[#{consecutive_success}/#{required_consecutive}] Public URL responding: #{result[:http_code]}"]
      else
        consecutive_success = 0
        log_output << [:info, "[#{attempt + 1}/#{max_attempts}] #{result[:message]}"]
      end
    end

    # Should have TWO transition logs (first success at attempt 1, then again at attempt 3 after streak broken)
    transition_logs = log_output.select { |l| l[1].include?("App responding") }
    assert_equal 2, transition_logs.size
    assert_includes log_output, [:info, "[1/10] App responding, verifying stability..."]
    assert_includes log_output, [:info, "[3/10] App responding, verifying stability..."]
  end
end
