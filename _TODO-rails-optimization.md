# NVOI Gem - Rails Optimization TODO

Changes needed in the `nvoi` gem to support **optional** dashboard integration.

---

## Modes

### Standalone Mode (default)

No `callback_url` in config. Gem works exactly as today:

```
nvoi deploy
    ↓
logs to stdout
    ↓
done
```

### Dashboard Mode (optional)

When `callback_url` is set in config:

```
nvoi deploy
    ↓
logs to stdout AND POSTs to callback_url
    ↓
Rails dashboard receives logs in real-time
```

**The gem remains 100% standalone.** Dashboard integration is opt-in via config.

---

## Architecture (Dashboard Mode)

```
CI (GitHub Actions, GitLab CI, etc.)
    ↓
gem install nvoi && nvoi deploy
    ↓
gem decrypts deploy.enc with DEPLOY_KEY
    ↓
gem POSTs logs to callback_url (signed with DEPLOY_KEY)
    ↓
Rails receives, stores, broadcasts via Turbo
```

**One key, two purposes (when dashboard enabled):**

1. Decrypt `deploy.enc`
2. HMAC-sign API callbacks to Rails

---

## 1. Callback Configuration

Add optional callback URL to deploy config schema:

```ruby
# lib/nvoi/configuration/deploy.rb
class Deploy
  # Existing fields...

  # New: callback URL for log streaming
  def callback_url
    @data["callback_url"]
  end

  def callback_enabled?
    callback_url.present?
  end
end
```

Config example:

```yaml
# In decrypted deploy config
callback_url: "https://myapp.com/api/deploys"
```

---

## 2. HTTP Logger Adapter

New adapter that POSTs logs to Rails:

```ruby
# lib/nvoi/adapters/logger/http.rb
module Nvoi
  module Adapters
    module Logger
      class Http < Base
        def initialize(url:, key:, deploy_id:, fallback: nil)
          @url = url
          @key = key
          @deploy_id = deploy_id
          @fallback = fallback || Stdout.new
          @buffer = []
          @flush_thread = start_flush_thread
        end

        def info(message, *args)
          log(:info, format_message(message, args))
        end

        def success(message, *args)
          log(:success, format_message(message, args))
        end

        def error(message, *args)
          log(:error, format_message(message, args))
        end

        def warning(message, *args)
          log(:warning, format_message(message, args))
        end

        def step(message, *args)
          log(:step, format_message(message, args))
        end

        def ok(message, *args)
          log(:ok, format_message(message, args))
        end

        def flush
          return if @buffer.empty?

          logs = @buffer.dup
          @buffer.clear

          send_logs(logs)
        end

        def close
          @flush_thread&.kill
          flush
          send_status(:completed)
        end

        def fail!(error_message)
          flush
          send_status(:failed, error: error_message)
        end

        private

        def log(level, message)
          @fallback&.public_send(level, message)

          @buffer << {
            level: level,
            message: message,
            logged_at: Time.now.iso8601(3)
          }
        end

        def start_flush_thread
          Thread.new do
            loop do
              sleep 1
              flush
            end
          end
        end

        def send_logs(logs)
          payload = { logs: logs }
          post("#{@url}/#{@deploy_id}/logs", payload)
        rescue => e
          @fallback&.warning("Callback failed: #{e.message}")
        end

        def send_status(status, error: nil)
          payload = { status: status, error: error }
          post("#{@url}/#{@deploy_id}/status", payload)
        rescue => e
          @fallback&.warning("Status callback failed: #{e.message}")
        end

        def post(url, payload)
          body = payload.to_json
          signature = sign(body)

          uri = URI(url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"

          request = Net::HTTP::Post.new(uri.path)
          request["Content-Type"] = "application/json"
          request["X-Nvoi-Signature"] = signature
          request["X-Nvoi-Deploy-Id"] = @deploy_id
          request.body = body

          response = http.request(request)

          unless response.is_a?(Net::HTTPSuccess)
            raise "HTTP #{response.code}: #{response.body}"
          end
        end

        def sign(body)
          "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", @key, body)
        end
      end
    end
  end
end
```

---

## 3. CLI Integration

Update deploy command to use HTTP logger when callback configured:

```ruby
# lib/nvoi/cli/deploy/command.rb
def run
  @log = build_logger

  # ... existing deploy logic ...

  @log.close  # flush remaining logs + send completed status
rescue => e
  @log.fail!(e.message)
  raise
end

private

def build_logger
  if @config.callback_enabled?
    deploy_id = ENV["NVOI_DEPLOY_ID"] || ENV["GITHUB_RUN_ID"] || SecureRandom.uuid

    Adapters::Logger::Http.new(
      url: @config.callback_url,
      key: load_deploy_key,
      deploy_id: deploy_id,
      fallback: Utils::Logger.new  # still print to stdout
    )
  else
    Utils::Logger.new
  end
end

def load_deploy_key
  key_path = resolve_key_path
  File.read(key_path).strip
end
```

---

## 4. Status Callbacks

Send deploy lifecycle events:

```ruby
# Callback payloads:

# POST /api/deploys/:id/logs
{
  "logs": [
    { "level": "info", "message": "Starting deploy...", "logged_at": "2024-01-15T10:30:00.123Z" },
    { "level": "success", "message": "Server provisioned", "logged_at": "2024-01-15T10:30:05.456Z" }
  ]
}

# POST /api/deploys/:id/status
{
  "status": "started",
  "git_sha": "abc123",
  "git_ref": "main",
  "ci_provider": "github_actions",
  "ci_run_url": "https://github.com/user/repo/actions/runs/12345"
}

# POST /api/deploys/:id/status (on complete)
{
  "status": "completed",
  "tunnels": [
    { "service_name": "web", "hostname": "www.example.com" }
  ],
  "duration_seconds": 120
}

# POST /api/deploys/:id/status (on failure)
{
  "status": "failed",
  "error": "SSH connection failed"
}
```

---

## 5. Delete Command Callbacks

Same pattern for delete:

```ruby
# lib/nvoi/cli/delete/command.rb
def run
  @log = build_logger
  send_status(:started)

  # ... existing delete logic ...

  send_status(:completed)
  @log.close
rescue => e
  send_status(:failed, error: e.message)
  @log.close
  raise
end
```

---

## 6. Environment Variables

CI provides context:

| Variable            | Source                      | Purpose                  |
| ------------------- | --------------------------- | ------------------------ |
| `NVOI_DEPLOY_ID`    | Set by CI or auto-generated | Unique deploy identifier |
| `GITHUB_RUN_ID`     | GitHub Actions              | Fallback deploy ID       |
| `GITHUB_SHA`        | GitHub Actions              | Git commit SHA           |
| `GITHUB_REF_NAME`   | GitHub Actions              | Branch name              |
| `GITHUB_SERVER_URL` | GitHub Actions              | Build CI run URL         |
| `GITHUB_REPOSITORY` | GitHub Actions              | repo owner/name          |
| `GITHUB_RUN_ID`     | GitHub Actions              | Run ID for URL           |

---

## 7. File Structure

```
lib/nvoi/
  adapters/
    logger/
      base.rb
      http.rb      # NEW
      stdout.rb    # renamed from utils/logger.rb
      null.rb
  cli/
    deploy/
      command.rb   # MODIFIED - use callback logger
    delete/
      command.rb   # MODIFIED - use callback logger
```

---

## 8. Onboard Wizard Enhancement

Add callback URL step:

```ruby
# lib/nvoi/cli/onboard/steps/callback_step.rb
class CallbackStep
  def run(state)
    use_callback = prompt.yes?("Stream deploy logs to a dashboard?")
    return state unless use_callback

    url = prompt.ask("Callback URL:", required: true)

    state.merge(callback_url: url)
  end
end
```

---

## 9. Testing

```ruby
# test/nvoi/adapters/logger/http_test.rb
class HttpLoggerTest < Minitest::Test
  def setup
    @url = "https://example.com/api/deploys"
    @key = "test-key-123"
    @deploy_id = "run-456"
  end

  def test_signs_requests_with_hmac
    stub_request(:post, "#{@url}/#{@deploy_id}/logs")
      .with { |req|
        signature = req.headers["X-Nvoi-Signature"]
        expected = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", @key, req.body)
        signature == expected
      }
      .to_return(status: 200)

    logger = Nvoi::Adapters::Logger::Http.new(
      url: @url, key: @key, deploy_id: @deploy_id
    )
    logger.info("test")
    logger.flush
  end

  def test_buffers_and_flushes
    stub = stub_request(:post, "#{@url}/#{@deploy_id}/logs")
      .to_return(status: 200)

    logger = Nvoi::Adapters::Logger::Http.new(
      url: @url, key: @key, deploy_id: @deploy_id
    )

    logger.info("one")
    logger.info("two")
    logger.flush

    assert_requested(stub, times: 1)
  end
end
```

---

## 10. Migration Path

1. Add HTTP logger adapter (non-breaking)
2. Add callback_url config option (non-breaking)
3. Update CLI to use callback logger when configured (non-breaking)
4. Update onboard wizard (non-breaking)
5. Release as 0.3.0

No breaking changes for existing CLI users.
