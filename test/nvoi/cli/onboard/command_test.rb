# frozen_string_literal: true

require "test_helper"
require "ostruct"
require "tty/prompt/test"
require "webmock/minitest"
require "nvoi/cli/onboard/command"

class TestOnboardCommand < Minitest::Test
  def setup
    WebMock.disable_net_connect!
    FileUtils.rm_f("deploy.enc")
    FileUtils.rm_f("deploy.key")
  end

  def teardown
    WebMock.reset!
    FileUtils.rm_f("deploy.enc")
    FileUtils.rm_f("deploy.key")
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

    stub_hetzner_api

    cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
    cmd.run

    assert File.exist?("deploy.enc"), "deploy.enc should be created"
    assert File.exist?("deploy.key"), "deploy.key should be created"
  end

  def test_full_hetzner_flow
    prompt = TTY::Prompt::Test.new

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

    stub_hetzner_api

    cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
    cmd.run

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

    # First two tokens fail, third succeeds
    stub_request(:get, "https://api.hetzner.cloud/v1/server_types")
      .with(headers: { "Authorization" => "Bearer bad_token" })
      .to_return(status: 401, body: { error: { message: "invalid token" } }.to_json, headers: json_headers)

    stub_request(:get, "https://api.hetzner.cloud/v1/server_types")
      .with(headers: { "Authorization" => "Bearer bad_token2" })
      .to_return(status: 401, body: { error: { message: "invalid token" } }.to_json, headers: json_headers)

    stub_request(:get, "https://api.hetzner.cloud/v1/server_types")
      .with(headers: { "Authorization" => "Bearer good_token" })
      .to_return(status: 200, body: hetzner_server_types_response.to_json, headers: json_headers)

    stub_request(:get, "https://api.hetzner.cloud/v1/datacenters")
      .with(headers: { "Authorization" => "Bearer good_token" })
      .to_return(status: 200, body: hetzner_datacenters_response.to_json, headers: json_headers)

    cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
    cmd.run

    output = prompt.output.string
    assert_match(/Invalid/, output)
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

    stub_aws_api

    cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
    cmd.run

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

    stub_scaleway_api

    cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
    cmd.run

    output = prompt.output.string
    assert_match(/myapp/, output)
  end

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

    stub_hetzner_api

    cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
    cmd.run

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

    stub_hetzner_api
    stub_cloudflare_api

    cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
    cmd.run

    output = prompt.output.string
    assert_match(/Cloudflare/, output)
    assert_match(/example\.com/, output)
    assert_match(/staging/, output)
  end

  def test_worker_no_port_skips_domain_selection
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
    prompt.input << "\n"                # no pre-run
    prompt.input << "n\n"               # no more apps
    prompt.input << "\e[B\e[B\e[B\r"    # no database
    prompt.input << "\e[B\e[B\r"        # done with env
    prompt.input << "\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\r"  # Cancel (9th option)
    prompt.input << "y\n"               # confirm discard
    prompt.input.rewind

    stub_hetzner_api
    stub_cloudflare_api

    cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
    cmd.run

    output = prompt.output.string
    assert_match(/solid_worker/, output)
    refute_match(/example\.com.*solid_worker/, output)
  end

  def test_cloudflare_skip_domain
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

    stub_hetzner_api
    stub_cloudflare_api

    cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
    cmd.run

    output = prompt.output.string
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

    stub_hetzner_api

    cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
    cmd.run

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
    prompt.input << "\e[B\e[B\e[B\e[B\r" # Edit apps (5th option)
    prompt.input << "\r"                # Select "web" app
    prompt.input << "\e[B\r"            # Select "Delete" action
    prompt.input << "y\n"               # confirm delete
    prompt.input << "\e[B\e[B\r"        # Done (3rd: worker, Add new, Done)
    prompt.input << "\e[B\e[B\e[B\e[B\e[B\e[B\e[B\e[B\r"  # Cancel
    prompt.input << "y\n"               # confirm discard
    prompt.input.rewind

    stub_hetzner_api

    cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
    cmd.run

    output = prompt.output.string
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

    stub_hetzner_api
    stub_cloudflare_api_with_subdomain_taken

    cmd = Nvoi::Cli::Onboard::Command.new(prompt:)
    cmd.run

    output = prompt.output.string
    assert_match(/taken/, output)
    assert_match(/available/, output)
  end

  private

    def json_headers
      { "Content-Type" => "application/json" }
    end

    # Hetzner API stubs

    def stub_hetzner_api
      stub_request(:get, "https://api.hetzner.cloud/v1/server_types")
        .to_return(status: 200, body: hetzner_server_types_response.to_json, headers: json_headers)

      stub_request(:get, "https://api.hetzner.cloud/v1/datacenters")
        .to_return(status: 200, body: hetzner_datacenters_response.to_json, headers: json_headers)
    end

    def hetzner_server_types_response
      {
        server_types: [
          { id: 1, name: "cx22", description: "CX22", cores: 2, memory: 4, disk: 40, cpu_type: "shared", architecture: "x86",
            prices: [{ "location" => "fsn1", "price_monthly" => { "gross" => "4.35" } }] },
          { id: 2, name: "cx32", description: "CX32", cores: 4, memory: 8, disk: 80, cpu_type: "shared", architecture: "x86",
            prices: [{ "location" => "fsn1", "price_monthly" => { "gross" => "8.79" } }] }
        ]
      }
    end

    def hetzner_datacenters_response
      {
        datacenters: [
          { name: "fsn1-dc14", description: "Falkenstein DC14",
            location: { name: "fsn1", city: "Falkenstein", country: "DE" },
            server_types: { available: [1, 2], supported: [1, 2] } },
          { name: "nbg1-dc3", description: "Nuremberg DC3",
            location: { name: "nbg1", city: "Nuremberg", country: "DE" },
            server_types: { available: [1, 2], supported: [1, 2] } }
        ]
      }
    end

    # AWS API stubs

    def stub_aws_api
      # DescribeRegions
      stub_request(:post, /ec2\..*\.amazonaws\.com/)
        .with(body: /Action=DescribeRegions/)
        .to_return(status: 200, body: aws_describe_regions_response, headers: { "Content-Type" => "text/xml" })

      # DescribeInstanceTypes
      stub_request(:post, /ec2\..*\.amazonaws\.com/)
        .with(body: /Action=DescribeInstanceTypes/)
        .to_return(status: 200, body: aws_describe_instance_types_response, headers: { "Content-Type" => "text/xml" })
    end

    def aws_describe_regions_response
      <<~XML
        <DescribeRegionsResponse xmlns="http://ec2.amazonaws.com/doc/2016-11-15/">
          <requestId>test</requestId>
          <regionInfo>
            <item>
              <regionName>us-east-1</regionName>
              <regionEndpoint>ec2.us-east-1.amazonaws.com</regionEndpoint>
            </item>
            <item>
              <regionName>us-west-2</regionName>
              <regionEndpoint>ec2.us-west-2.amazonaws.com</regionEndpoint>
            </item>
          </regionInfo>
        </DescribeRegionsResponse>
      XML
    end

    def aws_describe_instance_types_response
      <<~XML
        <DescribeInstanceTypesResponse xmlns="http://ec2.amazonaws.com/doc/2016-11-15/">
          <requestId>test</requestId>
          <instanceTypeSet>
            <item>
              <instanceType>t3.micro</instanceType>
              <currentGeneration>true</currentGeneration>
              <vCpuInfo>
                <defaultVCpus>2</defaultVCpus>
              </vCpuInfo>
              <memoryInfo>
                <sizeInMiB>1024</sizeInMiB>
              </memoryInfo>
              <processorInfo>
                <supportedArchitectures>
                  <item>x86_64</item>
                </supportedArchitectures>
              </processorInfo>
            </item>
            <item>
              <instanceType>t3.small</instanceType>
              <currentGeneration>true</currentGeneration>
              <vCpuInfo>
                <defaultVCpus>2</defaultVCpus>
              </vCpuInfo>
              <memoryInfo>
                <sizeInMiB>2048</sizeInMiB>
              </memoryInfo>
              <processorInfo>
                <supportedArchitectures>
                  <item>x86_64</item>
                </supportedArchitectures>
              </processorInfo>
            </item>
          </instanceTypeSet>
        </DescribeInstanceTypesResponse>
      XML
    end

    # Scaleway API stubs

    def stub_scaleway_api
      stub_request(:get, %r{api\.scaleway\.com/instance/v1/zones/.*/products/servers})
        .to_return(status: 200, body: scaleway_server_types_response.to_json, headers: json_headers)
    end

    def scaleway_server_types_response
      {
        servers: {
          "DEV1-S" => { ncpus: 2, ram: 2_147_483_648, arch: "x86_64", hourly_price: 0.01 },
          "DEV1-M" => { ncpus: 3, ram: 4_294_967_296, arch: "x86_64", hourly_price: 0.02 }
        }
      }
    end

    # Cloudflare API stubs

    def stub_cloudflare_api
      stub_request(:get, "https://api.cloudflare.com/client/v4/user/tokens/verify")
        .to_return(status: 200, body: { success: true, result: { status: "active" } }.to_json, headers: json_headers)

      stub_request(:get, "https://api.cloudflare.com/client/v4/zones")
        .to_return(status: 200, body: cloudflare_zones_response.to_json, headers: json_headers)

      # subdomain_available? checks for existing DNS records - stub all zones
      stub_request(:get, %r{api\.cloudflare\.com/client/v4/zones/[^/]+/dns_records})
        .to_return(status: 200, body: { success: true, result: [] }.to_json, headers: json_headers)
    end

    def stub_cloudflare_api_with_subdomain_taken
      stub_request(:get, "https://api.cloudflare.com/client/v4/user/tokens/verify")
        .to_return(status: 200, body: { success: true, result: { status: "active" } }.to_json, headers: json_headers)

      stub_request(:get, "https://api.cloudflare.com/client/v4/zones")
        .to_return(status: 200, body: cloudflare_zones_response.to_json, headers: json_headers)

      # find_dns_record fetches ALL records, filters locally
      # Return "taken.example.com" record so it appears taken, "available.example.com" won't match
      stub_request(:get, %r{api\.cloudflare\.com/client/v4/zones/[^/]+/dns_records})
        .to_return(status: 200, body: {
          success: true,
          result: [
            { id: "123", name: "taken.example.com", type: "CNAME", content: "target.com" }
          ]
        }.to_json, headers: json_headers)
    end

    def cloudflare_zones_response
      {
        success: true,
        result: [
          { id: "zone_123", name: "example.com", status: "active" },
          { id: "zone_456", name: "mysite.io", status: "active" }
        ]
      }
    end
end
