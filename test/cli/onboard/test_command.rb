# frozen_string_literal: true

require "test_helper"
require "ostruct"
require "tty/prompt/test"
require "nvoi/cli/onboard/command"

class TestOnboardCommand < Minitest::Test
  def test_file_loads_without_test_helper
    # Verify the file can be required in isolation (catches missing requires)
    output = `ruby -e "require './lib/nvoi/cli/onboard/command'" 2>&1`
    assert $?.success?, "File failed to load in isolation: #{output}"
  end

  def test_save_config
    prompt = TTY::Prompt::Test.new

    prompt.input << "myapp\n"
    prompt.input << "\r"                # hetzner
    prompt.input << "token\n"
    prompt.input << "\r"                # server type
    prompt.input << "\r"                # location
    prompt.input << "n\n"               # no cloudflare
    prompt.input << "web\n"             # app name
    prompt.input << "\n"                # no command (Docker entrypoint)
    prompt.input << "3000\n"
    prompt.input << "\n"
    prompt.input << "n\n"               # no more apps
    prompt.input << "\e[B\e[B\e[B\r"    # no database
    prompt.input << "\e[B\e[B\r"        # done with env
    prompt.input << "\r"                # Save configuration (1st option)
    prompt.input.rewind

    with_hetzner_mock do
      cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
      cmd.run
    end

    assert File.exist?("deploy.enc"), "deploy.enc should be created"
    assert File.exist?("deploy.key"), "deploy.key should be created"
  end

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
    prompt.input << "\n"                # no pre-run
    prompt.input << "n\n"               # no more apps
    prompt.input << "\r"                # select postgres
    prompt.input << "myapp_prod\n"      # db name
    prompt.input << "myapp\n"           # db user
    prompt.input << "secret123\n"       # db password
    prompt.input << "\e[B\e[B\r"        # Done with env (down twice, select)
    prompt.input << "\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\r"  # Cancel (9th option)
    prompt.input << "y\n"               # confirm discard
    prompt.input.rewind

    with_hetzner_mock do
      cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
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
    prompt.input << "\n"                # pre-run
    prompt.input << "n\n"               # no more apps
    prompt.input << "\e[B\e[B\e[B\r"    # None for db (down 3x)
    prompt.input << "\e[B\e[B\r"        # Done for env
    prompt.input << "\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\r"  # Cancel (9th option)
    prompt.input << "y\n"               # confirm discard
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
      cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
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
    prompt.input << "n\n"
    prompt.input << "\e[B\e[B\e[B\r"    # None for db
    prompt.input << "\e[B\e[B\r"        # Done for env
    prompt.input << "\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\r"  # Cancel (9th option)
    prompt.input << "y\n"               # confirm discard
    prompt.input.rewind

    with_aws_mock do
      cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
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
    prompt.input << "n\n"
    prompt.input << "\e[B\e[B\e[B\r"    # None for db
    prompt.input << "\e[B\e[B\r"        # Done for env
    prompt.input << "\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\r"  # Cancel (9th option)
    prompt.input << "y\n"               # confirm discard
    prompt.input.rewind

    with_scaleway_mock do
      cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
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
    prompt.input << "y\n"               # add another
    prompt.input << "worker\n"          # second app
    prompt.input << "sidekiq\n"
    prompt.input << "\n"                # no port
    prompt.input << "\n"
    prompt.input << "n\n"               # done with apps
    prompt.input << "\e[B\e[B\e[B\r"    # no database
    prompt.input << "\e[B\e[B\r"        # done with env
    prompt.input << "\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\r"  # Cancel (9th option)
    prompt.input << "y\n"               # confirm discard
    prompt.input.rewind

    with_hetzner_mock do
      cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
      cmd.run
    end

    output = prompt.output.string
    assert_match(/web/, output)
    assert_match(/worker/, output)
  end

  def test_cloudflare_with_domain_selection
    prompt = TTY::Prompt::Test.new

    prompt.input << "myapp\n"
    prompt.input << "\r"                # hetzner
    prompt.input << "token\n"
    prompt.input << "\r"                # server type
    prompt.input << "\r"                # location
    prompt.input << "y\n"               # yes cloudflare
    prompt.input << "cf_token\n"        # cloudflare token
    prompt.input << "acc_123\n"         # cloudflare account id
    prompt.input << "api\n"             # app name
    prompt.input << "rails s\n"         # command
    prompt.input << "3000\n"            # port
    prompt.input << "\r"                # select first domain (example.com)
    prompt.input << "staging\n"         # subdomain
    prompt.input << "\n"                # no pre-run
    prompt.input << "n\n"               # no more apps
    prompt.input << "\e[B\e[B\e[B\r"    # no database
    prompt.input << "\e[B\e[B\r"        # done with env
    prompt.input << "\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\r"  # Cancel (9th option)
    prompt.input << "y\n"               # confirm discard
    prompt.input.rewind

    with_hetzner_mock do
      with_cloudflare_mock do
        cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
        cmd.run
      end
    end

    output = prompt.output.string
    # Verify cloudflare was configured and domain selection happened
    assert_match(/Cloudflare/, output)
    assert_match(/example\.com/, output)
    assert_match(/staging/, output)
  end

  def test_worker_no_port_skips_domain_selection
    # When cloudflare is configured but app has no port (background worker),
    # domain selection should be skipped entirely
    prompt = TTY::Prompt::Test.new

    prompt.input << "myapp\n"
    prompt.input << "\r"                # hetzner
    prompt.input << "token\n"
    prompt.input << "\r"                # server type
    prompt.input << "\r"                # location
    prompt.input << "y\n"               # yes cloudflare
    prompt.input << "cf_token\n"        # cloudflare token
    prompt.input << "acc_123\n"         # cloudflare account id
    prompt.input << "solid_worker\n"    # app name (background worker)
    prompt.input << "bin/solid_queue\n" # command
    prompt.input << "\n"                # NO port (worker doesn't need one)
    # Domain selection should be SKIPPED - no input needed for domain
    prompt.input << "\n"                # no pre-run
    prompt.input << "n\n"               # no more apps
    prompt.input << "\e[B\e[B\e[B\r"    # no database
    prompt.input << "\e[B\e[B\r"        # done with env
    prompt.input << "\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\r"  # Cancel (9th option)
    prompt.input << "y\n"               # confirm discard
    prompt.input.rewind

    with_hetzner_mock do
      with_cloudflare_mock do
        cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
        cmd.run
      end
    end

    output = prompt.output.string
    assert_match(/solid_worker/, output)
    # Should NOT have domain in output since no port was provided
    refute_match(/example\.com.*solid_worker/, output)
  end

  def test_cloudflare_skip_domain
    # Test that user can choose "Skip (no domain)" when domain selection appears
    prompt = TTY::Prompt::Test.new

    prompt.input << "myapp\n"
    prompt.input << "\r"                # hetzner
    prompt.input << "token\n"
    prompt.input << "\r"                # server type
    prompt.input << "\r"                # location
    prompt.input << "y\n"               # yes cloudflare
    prompt.input << "cf_token\n"        # cloudflare token
    prompt.input << "acc_123\n"         # cloudflare account id
    prompt.input << "api\n"             # app name (web app)
    prompt.input << "\n"                # no command
    prompt.input << "3000\n"            # HAS port - so domain selection appears
    prompt.input << "\e[B\e[B\r"        # Skip domain (3rd option)
    prompt.input << "\n"                # no pre-run
    prompt.input << "n\n"               # no more apps
    prompt.input << "\e[B\e[B\e[B\r"    # no database
    prompt.input << "\e[B\e[B\r"        # done with env
    prompt.input << "\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\r"  # Cancel (9th option)
    prompt.input << "y\n"               # confirm discard
    prompt.input.rewind

    with_hetzner_mock do
      with_cloudflare_mock do
        cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
        cmd.run
      end
    end

    output = prompt.output.string
    # Verify cloudflare setup and skip domain flow
    assert_match(/Cloudflare/, output)
    assert_match(/Skip.*no domain/i, output)
  end

  def test_edit_app_from_summary
    prompt = TTY::Prompt::Test.new

    prompt.input << "myapp\n"
    prompt.input << "\r"                # hetzner
    prompt.input << "token\n"
    prompt.input << "\r"                # server type
    prompt.input << "\r"                # location
    prompt.input << "n\n"               # no cloudflare
    prompt.input << "web\n"             # app name
    prompt.input << "\n"                # no command (Docker entrypoint)
    prompt.input << "3000\n"
    prompt.input << "\n"
    prompt.input << "n\n"               # no more apps
    prompt.input << "\e[B\e[B\e[B\r"    # no database
    prompt.input << "\e[B\e[B\r"        # done with env
    # Now at summary menu
    prompt.input << "\e[B\e[B\e[B\e[B\r" # Edit apps (5th option)
    prompt.input << "\r"                # Select "web" app
    prompt.input << "\r"                # Select "Edit" action
    prompt.input << "webserver\n"       # rename to webserver
    prompt.input << "rails s\n"         # new command
    prompt.input << "8080\n"            # new port
    prompt.input << "\n"                # no pre-run
    prompt.input << "\e[B\e[B\r"        # Done (3rd: webserver, Add new, Done)
    prompt.input << "\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\r"  # Cancel
    prompt.input << "y\n"               # confirm discard
    prompt.input.rewind

    with_hetzner_mock do
      cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
      cmd.run
    end

    output = prompt.output.string
    assert_match(/webserver/, output)
    assert_match(/8080/, output)
  end

  def test_delete_app_from_summary
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
    prompt.input << "y\n"               # add another
    prompt.input << "worker\n"          # second app
    prompt.input << "sidekiq\n"
    prompt.input << "\n"                # no port
    prompt.input << "\n"
    prompt.input << "n\n"               # done with apps
    prompt.input << "\e[B\e[B\e[B\r"    # no database
    prompt.input << "\e[B\e[B\r"        # done with env
    # Summary menu - delete web app
    prompt.input << "\e[B\e[B\e[B\e[B\r" # Edit apps (5th option)
    prompt.input << "\r"                # Select "web" app
    prompt.input << "\e[B\r"            # Select "Delete" action
    prompt.input << "y\n"               # confirm delete
    prompt.input << "\e[B\e[B\r"        # Done (3rd: worker, Add new, Done)
    prompt.input << "\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\r"  # Cancel
    prompt.input << "y\n"               # confirm discard
    prompt.input.rewind

    with_hetzner_mock do
      cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
      cmd.run
    end

    output = prompt.output.string
    # After deletion, summary should only show worker
    assert_match(/worker/, output)
  end

  def test_subdomain_unavailable_retry
    prompt = TTY::Prompt::Test.new

    prompt.input << "myapp\n"
    prompt.input << "\r"                # hetzner
    prompt.input << "token\n"
    prompt.input << "\r"                # server type
    prompt.input << "\r"                # location
    prompt.input << "y\n"               # yes cloudflare
    prompt.input << "cf_token\n"        # cloudflare token
    prompt.input << "acc_123\n"         # cloudflare account id
    prompt.input << "api\n"             # app name
    prompt.input << "rails s\n"         # command
    prompt.input << "3000\n"            # port
    prompt.input << "\r"                # select first domain
    prompt.input << "taken\n"           # subdomain - will fail (taken)
    prompt.input << "available\n"       # subdomain - will succeed
    prompt.input << "\n"                # no pre-run
    prompt.input << "n\n"               # no more apps
    prompt.input << "\e[B\e[B\e[B\r"    # no database
    prompt.input << "\e[B\e[B\r"        # done with env
    prompt.input << "\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\r"  # Cancel (9th option)
    prompt.input << "y\n"               # confirm discard
    prompt.input.rewind

    with_hetzner_mock do
      with_cloudflare_mock_subdomain_taken do
        cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
        cmd.run
      end
    end

    output = prompt.output.string
    # Verify retry flow - first "taken" then "available" subdomain
    assert_match(/taken/, output)
    assert_match(/available/, output)
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
      mock.expect :list_zones, [
        { id: "zone_123", name: "example.com", status: "active" },
        { id: "zone_456", name: "mysite.io", status: "active" }
      ]
      # subdomain_available? will be called for validation
      mock.expect :subdomain_available?, true, [String, String, String]

      Nvoi::External::Dns::Cloudflare.stub :new, mock do
        yield
      end
    end

    def with_cloudflare_mock_subdomain_taken
      call_count = 0
      mock = Minitest::Mock.new
      mock.expect :validate_credentials, true
      mock.expect :list_zones, [
        { id: "zone_123", name: "example.com", status: "active" }
      ]

      # First call returns false (taken), second returns true (available)
      Nvoi::External::Dns::Cloudflare.stub :new, ->(_token, _account_id) {
        fake_client = Object.new
        def fake_client.validate_credentials; true; end
        def fake_client.list_zones
          [{ id: "zone_123", name: "example.com", status: "active" }]
        end

        # Track calls to subdomain_available?
        @subdomain_calls ||= 0
        fake_client.define_singleton_method(:subdomain_available?) do |_zone_id, subdomain, _domain|
          # "taken" subdomain is not available, others are
          subdomain != "taken"
        end

        fake_client
      } do
        yield
      end
    end
end
