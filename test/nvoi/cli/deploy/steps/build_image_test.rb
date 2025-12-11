# frozen_string_literal: true

require "test_helper"
require_relative "../../../../../lib/nvoi/cli/deploy/steps/build_image"

class BuildImageStepTest < Minitest::Test
  def setup
    @mock_config = Minitest::Mock.new
    @mock_ssh = Minitest::Mock.new
    @mock_log = Minitest::Mock.new
    @mock_namer = Minitest::Mock.new

    @mock_config.expect(:namer, @mock_namer)
    @mock_namer.expect(:latest_image_tag, "myapp:latest")
  end

  def test_run_builds_and_deploys_image
    @mock_log.expect(:info, nil, ["Building Docker image: %s", "myapp:20240101"])

    # Mock the containerd build - use block for keyword arg matching
    mock_containerd = Minitest::Mock.new
    mock_containerd.expect(:build_and_deploy_image, nil) do |path, tag, **kwargs|
      path == "/app" && tag == "myapp:20240101" && kwargs[:cache_from] == "myapp:latest"
    end

    Nvoi::External::Containerd.stub(:new, mock_containerd) do
      @mock_log.expect(:success, nil, ["Image built: %s", "myapp:20240101"])

      step = Nvoi::Cli::Deploy::Steps::BuildImage.new(@mock_config, @mock_ssh, @mock_log)
      step.run("/app", "myapp:20240101")
    end

    @mock_log.verify
    mock_containerd.verify
  end
end
