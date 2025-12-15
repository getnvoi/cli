# frozen_string_literal: true

require "test_helper"

class OnboardEnvStepTest < Minitest::Test
  def test_step_initializes
    prompt = Minitest::Mock.new
    step = Nvoi::Cli::Onboard::Steps::Env.new(prompt, test_mode: true)

    assert_instance_of Nvoi::Cli::Onboard::Steps::Env, step
  end

  def test_step_includes_onboard_ui
    assert Nvoi::Cli::Onboard::Steps::Env.include?(Nvoi::Cli::Onboard::Ui)
  end
end
