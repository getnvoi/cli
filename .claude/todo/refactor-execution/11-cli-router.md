# 11 - CLI Router Execution

## Reference
Read from: `/Users/ben/Desktop/nvoi-rb/lib/nvoi/`

## Build

Create `lib/nvoi/cli.rb`:
- Thor routing only (~50-80 lines)
- Lazy requires for each command
- Delegates to `CLI::Deploy::Command`, `CLI::Delete::Command`, etc.

```ruby
# Structure
module Nvoi
  class CLI < Thor
    desc "deploy", "Deploy application"
    def deploy
      require_relative "cli/deploy/command"
      CLI::Deploy::Command.new(options).run
    end
    # ... etc
  end
end
```

## Validate

- [ ] `wc -l lib/nvoi/cli.rb` < 100 lines
- [ ] No business logic in cli.rb
- [ ] All commands delegate to `cli/*/command.rb`

## Test

```bash
cd /Users/ben/Desktop/nvoi-rb-refactor
ruby -e "require './lib/nvoi/cli'; p Nvoi::CLI"
```

## Commit

```bash
git add -A && git commit -m "Phase 11: Build cli.rb router"
```
