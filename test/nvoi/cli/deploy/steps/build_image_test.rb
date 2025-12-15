# frozen_string_literal: true

require "test_helper"

class BuildImageTest < Minitest::Test
  MockConfig = Struct.new(:namer, :container_prefix, :docker_platform, keyword_init: true)
  MockNamer = Struct.new(:prefix, keyword_init: true) do
    def latest_image_tag
      "#{prefix}:latest"
    end
  end

  def setup
    @log = Minitest::Mock.new
  end

  def test_run_builds_and_pushes_image
    namer = MockNamer.new(prefix: "myapp")
    config = MockConfig.new(namer:, container_prefix: "myapp", docker_platform: "linux/amd64")

    @log.expect(:info, nil, ["Building Docker image: %s", "myapp:20240101"])
    @log.expect(:info, nil, ["Tagging for registry: %s", String])
    @log.expect(:info, nil, ["Pushing to registry via SSH tunnel..."])
    @log.expect(:success, nil, ["Image built and pushed: %s", String])

    step = Nvoi::Cli::Deploy::Steps::BuildImage.new(config, @log)

    # Mock system calls
    system_calls = []
    step.define_singleton_method(:system) do |*args|
      system_calls << args
      true
    end

    result = step.run("/tmp/app", "myapp:20240101")

    assert_match(/localhost:\d+\/myapp:20240101/, result)
    @log.verify
  end

  def test_run_raises_on_build_failure
    namer = MockNamer.new(prefix: "myapp")
    config = MockConfig.new(namer:, container_prefix: "myapp", docker_platform: "linux/amd64")

    @log.expect(:info, nil, ["Building Docker image: %s", "myapp:20240101"])

    step = Nvoi::Cli::Deploy::Steps::BuildImage.new(config, @log)

    # Mock system call to fail
    step.define_singleton_method(:system) { |*_args| false }

    assert_raises(Nvoi::Errors::SshError) do
      step.run("/tmp/app", "myapp:20240101")
    end
  end
end
