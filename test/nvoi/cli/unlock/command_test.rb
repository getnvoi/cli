# frozen_string_literal: true

require "test_helper"

class UnlockCommandTest < Minitest::Test
  MockConfig = Struct.new(:server_name, :ssh_key_path, :namer, keyword_init: true)
  MockNamer = Struct.new(:prefix, keyword_init: true) do
    def deployment_lock_file_path
      "/tmp/nvoi-deploy-#{prefix}.lock"
    end
  end
  MockServer = Struct.new(:public_ipv4, keyword_init: true)

  def test_command_initializes
    options = { config: "deploy.enc", dir: "." }
    command = Nvoi::Cli::Unlock::Command.new(options)

    assert_instance_of Nvoi::Cli::Unlock::Command, command
  end
end
