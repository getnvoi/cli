# frozen_string_literal: true

require "test_helper"

class ProvisionServerTest < Minitest::Test
  MockConfig = Struct.new(:deploy, :namer, :ssh_key_path, :ssh_public_key, :provider_name, :hetzner, keyword_init: true)
  MockDeploy = Struct.new(:application, keyword_init: true)
  MockApplication = Struct.new(:servers, keyword_init: true)
  MockServerConfig = Struct.new(:count, :master, :type, :location, keyword_init: true)
  MockHetzner = Struct.new(:server_type, :server_location, keyword_init: true)
  MockNamer = Struct.new(:app_name, keyword_init: true) do
    def server_name(group, index)
      "#{app_name}-#{group}-#{index}"
    end
  end
  MockServer = Struct.new(:id, :public_ipv4, keyword_init: true)
  MockNetwork = Struct.new(:id, keyword_init: true)
  MockFirewall = Struct.new(:id, keyword_init: true)

  def setup
    @log = Minitest::Mock.new
    @provider = Minitest::Mock.new
    @network = MockNetwork.new(id: "net-123")
    @firewall = MockFirewall.new(id: "fw-456")
  end

  def test_run_returns_early_when_server_exists
    servers = { "master" => MockServerConfig.new(count: 1, master: true, type: nil, location: nil) }
    app = MockApplication.new(servers:)
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new(app_name: "myapp")
    hetzner = MockHetzner.new(server_type: "cx22", server_location: "fsn1")
    config = MockConfig.new(
      deploy:, namer:, ssh_key_path: "/tmp/key", ssh_public_key: "ssh-rsa AAAA",
      provider_name: "hetzner", hetzner:
    )

    existing_server = MockServer.new(id: "srv-existing", public_ipv4: "1.2.3.4")

    @log.expect(:info, nil, ["Provisioning servers"])
    @log.expect(:info, nil, ["Provisioning server: %s", "myapp-master-1"])
    @provider.expect(:find_server, existing_server, ["myapp-master-1"])
    @log.expect(:info, nil, ["Server already exists: %s (%s)", "myapp-master-1", "1.2.3.4"])
    @log.expect(:success, nil, ["All servers provisioned"])

    step = Nvoi::Cli::Deploy::Steps::ProvisionServer.new(config, @provider, @log, @network, @firewall)
    ip = step.run

    assert_equal "1.2.3.4", ip
    @provider.verify
    @log.verify
  end

  def test_run_skips_when_no_servers
    app = MockApplication.new(servers: {})
    deploy = MockDeploy.new(application: app)
    namer = MockNamer.new(app_name: "myapp")
    config = MockConfig.new(
      deploy:, namer:, ssh_key_path: "/tmp/key", ssh_public_key: "ssh-rsa AAAA",
      provider_name: "hetzner", hetzner: nil
    )

    @log.expect(:info, nil, ["Provisioning servers"])
    @log.expect(:success, nil, ["All servers provisioned"])

    step = Nvoi::Cli::Deploy::Steps::ProvisionServer.new(config, @provider, @log, @network, @firewall)
    result = step.run

    assert_nil result
    @log.verify
  end
end
