# frozen_string_literal: true

require "test_helper"

class OnboardComputeStepTest < Minitest::Test
  def setup
    @prompt = Minitest::Mock.new
  end

  def test_providers_constant
    providers = Nvoi::Cli::Onboard::Steps::Compute::PROVIDERS

    assert_equal 3, providers.size
    assert_equal :hetzner, providers[0][:value]
    assert_equal :aws, providers[1][:value]
    assert_equal :scaleway, providers[2][:value]
  end

  def test_initializes_with_prompt
    step = Nvoi::Cli::Onboard::Steps::Compute.new(@prompt, test_mode: true)

    assert_instance_of Nvoi::Cli::Onboard::Steps::Compute, step
  end
end
