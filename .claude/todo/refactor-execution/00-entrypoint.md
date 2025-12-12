# Refactor Execution Entrypoint

## Strategy

**Clean slate rebuild.** Not migration.

- **Reference codebase:** `/Users/ben/Desktop/nvoi-rb/` (working code, read-only)
- **Worktree:** `/Users/ben/Desktop/nvoi-rb-refactor/` (clean slate, write here)

## Setup

```bash
# Clear worktree lib/nvoi/ (keep exe/, test/, templates/, etc.)
cd /Users/ben/Desktop/nvoi-rb-refactor
rm -rf lib/nvoi
mkdir lib/nvoi
```

## Execution Order

Each phase: **build → validate → test → commit**

```
Phase 1: 01-objects.md      → Build objects/ from scratch
Phase 2: 02-utils.md        → Build utils/ from scratch
Phase 3: 03-external-cloud.md → Build external/cloud/
Phase 4: 04-external-dns.md   → Build external/dns/
Phase 5: 05-external-other.md → Build external/ssh, kubectl, containerd, database
Phase 6: 06-cli-deploy.md     → Build cli/deploy/
Phase 7: 07-cli-delete.md     → Build cli/delete/
Phase 8: 08-cli-exec.md       → Build cli/exec/
Phase 9: 09-cli-credentials.md → Build cli/credentials/
Phase 10: 10-cli-db.md        → Build cli/db/
Phase 11: 11-cli-router.md    → Build cli.rb
Phase 12: 12-cleanup.md       → Final wiring, lib/nvoi.rb, version.rb
```

## Per-Phase Protocol

1. **Build** - Create new files reading from reference
2. **Validate** - User reviews structure
3. **Test** - `bundle exec rake test`
4. **Commit** - Only after tests pass

## Current Step

**NOT STARTED**

Next: Clear worktree, then `01-objects.md`
