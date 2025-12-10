# frozen_string_literal: true

require "test_helper"

module Nvoi
  module Deployer
    class ServiceDeployerTest < Minitest::Test
      def setup
        @config = mock_config
        @ssh = MockSSH.new
        @log = MockLogger.new
        @deployer = ServiceDeployer.new(@config, @ssh, @log)
      end

      # check_public_url tests

      def test_check_public_url_success_with_200_and_no_error_header
        @ssh.stub_response(<<~RESPONSE)
          HTTP/2 200
          content-type: text/html
          date: Mon, 01 Jan 2024 00:00:00 GMT
        RESPONSE

        result = @deployer.check_public_url(@ssh, "https://example.com/up")

        assert result[:success]
        assert_equal "200", result[:http_code]
        assert_equal "OK", result[:message]
      end

      def test_check_public_url_fails_when_error_header_present
        @ssh.stub_response(<<~RESPONSE)
          HTTP/2 200
          content-type: text/html
          x-nvoi-error: true
          date: Mon, 01 Jan 2024 00:00:00 GMT
        RESPONSE

        result = @deployer.check_public_url(@ssh, "https://example.com/up")

        refute result[:success]
        assert_equal "200", result[:http_code]
        assert_includes result[:message], "X-Nvoi-Error header present"
        assert_includes result[:message], "app is down"
      end

      def test_check_public_url_fails_when_error_header_present_case_insensitive
        @ssh.stub_response(<<~RESPONSE)
          HTTP/2 200
          content-type: text/html
          X-NVOI-ERROR: true
          date: Mon, 01 Jan 2024 00:00:00 GMT
        RESPONSE

        result = @deployer.check_public_url(@ssh, "https://example.com/up")

        refute result[:success]
        assert_includes result[:message], "X-Nvoi-Error header present"
      end

      def test_check_public_url_fails_with_non_200_status
        @ssh.stub_response(<<~RESPONSE)
          HTTP/1.1 503 Service Unavailable
          content-type: text/html
        RESPONSE

        result = @deployer.check_public_url(@ssh, "https://example.com/up")

        refute result[:success]
        assert_equal "503", result[:http_code]
        assert_includes result[:message], "HTTP 503"
      end

      def test_check_public_url_handles_http1_response
        @ssh.stub_response(<<~RESPONSE)
          HTTP/1.1 200 OK
          content-type: text/html
        RESPONSE

        result = @deployer.check_public_url(@ssh, "https://example.com/up")

        assert result[:success]
        assert_equal "200", result[:http_code]
      end

      def test_check_public_url_handles_empty_response
        @ssh.stub_response("")

        result = @deployer.check_public_url(@ssh, "https://example.com/up")

        refute result[:success]
        assert_equal "000", result[:http_code]
      end

      private

        def mock_config
          config = Object.new
          namer = Object.new

          def namer.app_secret_name
            "test-app-secret"
          end

          def config.namer
            @namer ||= Object.new.tap do |n|
              def n.app_secret_name
                "test-app-secret"
              end
            end
          end

          def config.deploy
            @deploy ||= Object.new.tap do |d|
              def d.application
                @app ||= Object.new.tap do |a|
                  def a.servers
                    {}
                  end
                end
              end
            end
          end

          config
        end

        class MockSSH
          attr_accessor :last_command

          def initialize
            @response = ""
          end

          def stub_response(response)
            @response = response
          end

          def execute(cmd)
            @last_command = cmd
            @response
          end
        end

        class MockLogger
          def info(*); end
          def success(*); end
          def warning(*); end
          def error(*); end
        end
    end
  end
end
