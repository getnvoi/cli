# frozen_string_literal: true

require "test_helper"
require "tty/prompt/test"
require "nvoi/cli/onboard/command"

class TestOnboardCommand < Minitest::Test
  def setup
    # Clean up any test files
    FileUtils.rm_f("deploy.enc")
    FileUtils.rm_f("deploy.key")
  end

  def teardown
    FileUtils.rm_f("deploy.enc")
    FileUtils.rm_f("deploy.key")
  end

  def test_full_hetzner_flow
    prompt = TTY::Prompt::Test.new

    # Simulate all inputs in order
    prompt.input << "myapp\n"           # app name
    prompt.input << "\r"                # select hetzner (first option)
    prompt.input << "fake_token\n"      # api token
    prompt.input << "\r"                # select first server type
    prompt.input << "\r"                # select first location
    prompt.input << "n\n"               # no cloudflare
    prompt.input << "web\n"             # app name
    prompt.input << "bundle exec puma\n" # command
    prompt.input << "3000\n"            # port
    prompt.input << "\n"                # no domain
    prompt.input << "\n"                # no pre-run
    prompt.input << "n\n"               # no more apps
    prompt.input << "\r"                # select postgres
    prompt.input << "myapp_prod\n"      # db name
    prompt.input << "myapp\n"           # db user
    prompt.input << "secret123\n"       # db password
    prompt.input << "\e[B\e[B\r"        # Done with env (down twice, select)
    prompt.input << "n\n"               # don't save (test file creation separately)
    prompt.input.rewind

    with_hetzner_mock do
      cmd = Nvoi::Cli::Onboard::Command.new(prompt: prompt)
      cmd.run
    end

    # Verify output contains expected text
    output = prompt.output.string
    assert_match(/myapp/, output)
    assert_match(/Hetzner/i, output)
    assert_match(/postgres/i, output)
  end

  def test_retry_on_invalid_credentials
    prompt = TTY::Prompt::Test.new

    prompt.input << "myapp\n"
    prompt.input << "\r"                # hetzner
    prompt.input << "bad_token\n"       # first attempt - will fail
    prompt.input << "bad_token2\n"      # second attempt - will fail
    prompt.input << "good_token\n"      # third attempt - will work
    prompt.input << "\r"                # server type
    prompt.input << "\r"                # location
    prompt.input << "n\n"               # no cloudflare
    prompt.input << "api\n"             # app name
    prompt.input << "rails s\n"         # command
    prompt.input << "3000\n"            # port
    prompt.input << "\n"                # domain
    prompt.input << "\n"                # pre-run
    prompt.input << "n\n"               # no more apps
    prompt.input << "\e[B\e[B\e[B\r"    # None for db (down 3x)
    prompt.input << "\e[B\e[B\r"        # Done for env
    prompt.input << "n\n"               # don't save
    prompt.input.rewind

    call_count = 0

    # First two calls fail, third succeeds
    Nvoi::External::Cloud::Hetzner.stub :new, ->(_token) {
      call_count += 1
      mock = Minitest::Mock.new
      if call_count < 3
        mock.expect :validate_credentials, nil do
          raise Nvoi::Errors::ValidationError, "Invalid token"
        end
      else
        mock.expect :validate_credentials, true
        mock.expect :list_server_types, [{ name: "cx22", description: "test", cores: 2, memory: 4096, disk: 40, price: "4.35" }]
        mock.expect :list_locations, [{ name: "fsn1", city: "Falkenstein", country: "DE", description: "test" }]
      end
      mock
    } do
      cmd = Nvoi::Cli::Onboard::Command.new(prompt: prompt)
      cmd.run
    end

    assert_equal 3, call_count, "Should have tried 3 times"
  end

  def test_aws_flow
    prompt = TTY::Prompt::Test.new

    prompt.input << "myapp\n"
    prompt.input << "\e[B\r"            # down + enter to select AWS
    prompt.input << "AKIAIOSFODNN7EXAMPLE\n"  # access key
    prompt.input << "secret\n"          # secret key
    prompt.input << "\r"                # select first region
    prompt.input << "\r"                # select first instance type
    prompt.input << "n\n"               # no cloudflare
    prompt.input << "api\n"
    prompt.input << "node server.js\n"
    prompt.input << "8080\n"
    prompt.input << "\n"
    prompt.input << "\n"
    prompt.input << "n\n"
    prompt.input << "\e[B\e[B\e[B\r"    # None for db
    prompt.input << "\e[B\e[B\r"        # Done for env
    prompt.input << "n\n"
    prompt.input.rewind

    with_aws_mock do
      cmd = Nvoi::Cli::Onboard::Command.new(prompt: prompt)
      cmd.run
    end

    output = prompt.output.string
    assert_match(/myapp/, output)
  end

  def test_scaleway_flow
    prompt = TTY::Prompt::Test.new

    prompt.input << "myapp\n"
    prompt.input << "\e[B\e[B\r"        # down twice to select Scaleway
    prompt.input << "scw-secret-key\n"  # secret key
    prompt.input << "project-123\n"     # project id
    prompt.input << "\r"                # select first zone
    prompt.input << "\r"                # select first server type
    prompt.input << "n\n"               # no cloudflare
    prompt.input << "api\n"
    prompt.input << "python app.py\n"
    prompt.input << "5000\n"
    prompt.input << "\n"
    prompt.input << "\n"
    prompt.input << "n\n"
    prompt.input << "\e[B\e[B\e[B\r"    # None for db
    prompt.input << "\e[B\e[B\r"        # Done for env
    prompt.input << "n\n"
    prompt.input.rewind

    with_scaleway_mock do
      cmd = Nvoi::Cli::Onboard::Command.new(prompt: prompt)
      cmd.run
    end

    output = prompt.output.string
    assert_match(/myapp/, output)
  end

  # Note: Ctrl+C handling is difficult to test with TTY::Prompt::Test
  # because empty input just blocks rather than raising InputInterrupt.
  # The error handling in the command is tested manually.

  def test_multiple_apps
    prompt = TTY::Prompt::Test.new

    prompt.input << "myapp\n"
    prompt.input << "\r"                # hetzner
    prompt.input << "token\n"
    prompt.input << "\r"                # server type
    prompt.input << "\r"                # location
    prompt.input << "n\n"               # no cloudflare
    prompt.input << "web\n"             # first app
    prompt.input << "puma\n"
    prompt.input << "3000\n"
    prompt.input << "\n"
    prompt.input << "\n"
    prompt.input << "y\n"               # add another
    prompt.input << "worker\n"          # second app
    prompt.input << "sidekiq\n"
    prompt.input << "\n"                # no port
    prompt.input << "\n"
    prompt.input << "\n"
    prompt.input << "n\n"               # done with apps
    prompt.input << "\e[B\e[B\e[B\r"    # no database
    prompt.input << "\e[B\e[B\r"        # done with env
    prompt.input << "n\n"               # don't save
    prompt.input.rewind

    with_hetzner_mock do
      cmd = Nvoi::Cli::Onboard::Command.new(prompt: prompt)
      cmd.run
    end

    output = prompt.output.string
    assert_match(/web/, output)
    assert_match(/worker/, output)
  end

  def test_cloudflare_validation
    prompt = TTY::Prompt::Test.new

    prompt.input << "myapp\n"
    prompt.input << "\r"                # hetzner
    prompt.input << "token\n"
    prompt.input << "\r"
    prompt.input << "\r"
    prompt.input << "y\n"               # yes cloudflare
    prompt.input << "cf_token\n"
    prompt.input << "acc_123\n"
    prompt.input << "api\n"
    prompt.input << "rails s\n"
    prompt.input << "3000\n"
    prompt.input << "\n"
    prompt.input << "\n"
    prompt.input << "n\n"
    prompt.input << "\e[B\e[B\e[B\r"
    prompt.input << "\e[B\e[B\r"
    prompt.input << "n\n"
    prompt.input.rewind

    with_hetzner_mock do
      with_cloudflare_mock do
        cmd = Nvoi::Cli::Onboard::Command.new(prompt: prompt)
        cmd.run
      end
    end

    output = prompt.output.string
    assert_match(/Cloudflare/, output)
  end

  private

  def with_hetzner_mock
    mock = Minitest::Mock.new
    mock.expect :validate_credentials, true
    mock.expect :list_server_types, [
      { name: "cx22", description: "CX22", cores: 2, memory: 4096, disk: 40, price: "4.35" },
      { name: "cx32", description: "CX32", cores: 4, memory: 8192, disk: 80, price: "8.79" }
    ]
    mock.expect :list_locations, [
      { name: "fsn1", city: "Falkenstein", country: "DE", description: "DC14" },
      { name: "nbg1", city: "Nuremberg", country: "DE", description: "DC3" }
    ]

    Nvoi::External::Cloud::Hetzner.stub :new, mock do
      yield
    end
  end

  def with_aws_mock
    mock = Minitest::Mock.new
    mock.expect :validate_credentials, true
    mock.expect :list_regions, [
      { name: "us-east-1", endpoint: "ec2.us-east-1.amazonaws.com" },
      { name: "us-west-2", endpoint: "ec2.us-west-2.amazonaws.com" }
    ]
    mock.expect :list_instance_types, [
      { name: "t3.micro", vcpus: 2, memory: 1024 },
      { name: "t3.small", vcpus: 2, memory: 2048 }
    ]

    Nvoi::External::Cloud::Aws.stub :new, mock do
      yield
    end
  end

  def with_scaleway_mock
    mock = Minitest::Mock.new
    mock.expect :list_zones, [
      { name: "fr-par-1", city: "Paris" },
      { name: "nl-ams-1", city: "Amsterdam" }
    ]
    mock.expect :validate_credentials, true
    mock.expect :list_server_types, [
      { name: "DEV1-S", cores: 2, ram: 2048, hourly_price: 0.01 }
    ]

    Nvoi::External::Cloud::Scaleway.stub :new, mock do
      yield
    end
  end

  def with_cloudflare_mock
    mock = Minitest::Mock.new
    mock.expect :validate_credentials, true

    Nvoi::External::Dns::Cloudflare.stub :new, mock do
      yield
    end
  end
end
