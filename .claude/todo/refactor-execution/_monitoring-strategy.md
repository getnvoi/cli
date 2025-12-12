# Monitoring Strategy

## Per-Step Validation

### After Every Step

```bash
bundle exec rake test          # Must pass
ruby -c lib/nvoi.rb            # Syntax check
```

---

## Step-Specific Assertions

### 01-objects
- [ ] `Objects::Server.new(id: "1", name: "x", status: "running", public_ipv4: "1.2.3.4")` works
- [ ] All Structs accessible under `Nvoi::Objects::`
- [ ] Old Struct definitions removed from source files
- [ ] All references updated to `Objects::`
- [ ] `grep -r "Providers::Server" lib/` returns nothing

### 02-utils
- [ ] `Utils::Logger.new` works
- [ ] `Utils::Namer.new(config).hostname("app", "example.com")` returns `"app.example.com"`
- [ ] `Utils::ConfigLoader.new.load(path)` returns config
- [ ] `Utils::Crypto` encrypts/decrypts
- [ ] Old files deleted: `logger.rb`, `constants.rb`, `errors.rb`, `config/naming.rb`, etc.
- [ ] `grep -r "Config::ResourceNamer" lib/` returns nothing

### 03-external-cloud
- [ ] `External::Cloud.for(config)` returns correct provider
- [ ] `External::Cloud::Hetzner.new(token)` instantiates
- [ ] Provider methods work: `find_server`, `create_server`, etc.
- [ ] `providers/` directory deleted
- [ ] `grep -r "Providers::Hetzner" lib/` returns nothing

### 04-external-dns
- [ ] `External::DNS::Cloudflare.new(token, account_id)` instantiates
- [ ] `setup_tunnel` method exists and callable
- [ ] `cloudflare/` directory deleted
- [ ] `grep -r "Cloudflare::Client" lib/` returns nothing

### 05-external-other
- [ ] `External::SSH.new(ip, key)` instantiates
- [ ] `External::Kubectl.new(ssh)` instantiates
- [ ] `External::Containerd.new(ssh)` instantiates
- [ ] `External::Database.provider_for("postgres")` returns provider
- [ ] `remote/` directory deleted
- [ ] `k8s/` directory deleted
- [ ] `database/` directory deleted
- [ ] `grep -r "Remote::SSHExecutor" lib/` returns nothing

### 06-cli-deploy
- [ ] `CLI::Deploy::Command.new(options).run` callable
- [ ] All steps in `cli/deploy/steps/` load without error
- [ ] Step order matches original flow
- [ ] `service/deploy.rb` deleted
- [ ] `steps/` directory deleted
- [ ] `deployer/` directory deleted
- [ ] `grep -r "Service::DeployService" lib/` returns nothing

### 07-cli-delete
- [ ] `CLI::Delete::Command.new(options).run` callable
- [ ] Teardown order preserved (detach → delete servers → delete volumes → etc.)
- [ ] `service/delete.rb` deleted
- [ ] `grep -r "Service::DeleteService" lib/` returns nothing

### 08-cli-exec
- [ ] `CLI::Exec::Command.new(options).run(["ls"])` callable
- [ ] `--all` flag works
- [ ] `-i` interactive works
- [ ] `service/exec.rb` deleted

### 09-cli-credentials
- [ ] `CLI::Credentials::Edit::Command.new(options).run` callable
- [ ] `CLI::Credentials::Show::Command.new(options).run` callable
- [ ] `credentials/` directory deleted

### 10-cli-db
- [ ] `CLI::Db::Command.new(options).branch_create` callable
- [ ] `branch_list`, `branch_restore`, `branch_download` callable
- [ ] `service/db.rb` deleted

### 11-cli-router
- [ ] `nvoi deploy --help` works
- [ ] `nvoi delete --help` works
- [ ] `nvoi exec --help` works
- [ ] `nvoi credentials --help` works
- [ ] `nvoi db --help` works
- [ ] `cli.rb` is < 100 lines
- [ ] `service/` directory deleted (should be empty by now)

### 12-cleanup
- [ ] No empty directories remain
- [ ] `tree lib/nvoi -L 2` matches expected structure
- [ ] Full test suite passes
- [ ] No orphan requires in `lib/nvoi.rb`

---

## Integration Smoke Test (End)

```bash
# Dry run (no actual cloud calls)
nvoi deploy --help
nvoi delete --help
nvoi exec --help
nvoi credentials show --help
nvoi db branch --help
```

If all help commands work → routing is correct.

---

## Rollback

If any step fails:
```bash
git checkout HEAD~1 -- .
# or
git reset --hard HEAD~1
```

Single commit = single rollback.
