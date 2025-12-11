# frozen_string_literal: true

require "test_helper"
require_relative "../../../../../lib/nvoi/cli/deploy/steps/cleanup_images"

class CleanupImagesStepTest < Minitest::Test
  def setup
    @mock_config = Minitest::Mock.new
    @mock_ssh = Minitest::Mock.new
    @mock_log = Minitest::Mock.new

    @mock_config.expect(:keep_count_value, 3)
    @mock_config.expect(:container_prefix, "myapp")
  end

  def test_run_cleans_old_images
    @mock_log.expect(:info, nil, ["Cleaning up old images (keeping %d)", 3])

    mock_containerd = Minitest::Mock.new
    mock_containerd.expect(:list_images, ["20240101", "20240102", "20240103", "20240104", "20240105"], ["myapp:*"])
    mock_containerd.expect(:cleanup_old_images, nil) do |prefix, keep_tags|
      prefix == "myapp" && keep_tags.include?("20240105") && keep_tags.include?("20240104")
    end

    Nvoi::External::Containerd.stub(:new, mock_containerd) do
      @mock_log.expect(:success, nil, ["Old images cleaned up"])

      step = Nvoi::Cli::Deploy::Steps::CleanupImages.new(@mock_config, @mock_ssh, @mock_log)
      step.run("20240105")
    end

    @mock_log.verify
  end
end
