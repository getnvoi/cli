# 09 - CLI Credentials Execution

## Reference
Read from: `/Users/ben/Desktop/nvoi-rb/lib/nvoi/`

## Build

Create `lib/nvoi/cli/credentials/edit/command.rb`:
- Edit logic from `credentials/editor.rb`
- Uses `Utils::Crypto`

Create `lib/nvoi/cli/credentials/show/command.rb`:
- Show logic from `credentials/editor.rb`
- Uses `Utils::Crypto`

Under `Nvoi::CLI::Credentials` namespace.

## Validate

- [ ] `ls lib/nvoi/cli/credentials/edit/` shows command.rb
- [ ] `ls lib/nvoi/cli/credentials/show/` shows command.rb

## Test

```bash
cd /Users/ben/Desktop/nvoi-rb-refactor
ruby -e "require './lib/nvoi/cli/credentials/edit/command'; p Nvoi::CLI::Credentials::Edit::Command"
```

## Commit

```bash
git add -A && git commit -m "Phase 9: Build cli/credentials/"
```
