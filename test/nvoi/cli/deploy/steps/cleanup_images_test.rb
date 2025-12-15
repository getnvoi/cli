# frozen_string_literal: true

require "test_helper"

class CleanupImagesTest < Minitest::Test
  MockConfig = Struct.new(:keep_count_value, :container_prefix, keyword_init: true)

  def setup
    @log = Minitest::Mock.new
    @ssh = Minitest::Mock.new
    @config = MockConfig.new(keep_count_value: 3, container_prefix: "myapp")
  end

  def test_run_cleans_old_images
    @log.expect(:info, nil, ["Cleaning up old images (keeping %d)", 3])
    @log.expect(:success, nil, ["Old images cleaned up"])

    # Mock containerd through SSH
    containerd = Minitest::Mock.new
    containerd.expect(:list_images, ["myapp:20240101", "myapp:20240102", "myapp:20240103", "myapp:20240104"], ["myapp:*"])
    containerd.expect(:cleanup_old_images, nil, ["myapp", ["myapp:20240104", "myapp:20240103", "myapp:20240102", "myapp:20240105", "latest"]])

    Nvoi::External::Containerd.stub(:new, containerd) do
      step = Nvoi::Cli::Deploy::Steps::CleanupImages.new(@config, @ssh, @log)
      step.run("myapp:20240105")
    end

    @log.verify
    containerd.verify
  end
end
