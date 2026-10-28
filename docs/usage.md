# Usage details

Extended usage beyond the minimal example in the [README](../README.md#how).

## Central hub (schedule + dispatch)

The repo includes a `mirror-all.yaml` workflow that reads `config/repos.yaml` and mirrors all
listed repos via matrix jobs.

## Local clone (script-only)

Mirror GitHub repos to a local directory using just `scripts/clone-local.sh` — no GitHub Actions,
no PATs, no GitLab/Codeberg. Bare `--mirror` clones; idempotent re-runs (auto-prune deletions on
subsequent fetches).

```bash
# All public repos for an owner
OWNER=qte77 ./scripts/clone-local.sh

# Subset from a curated list (same shape as config/repos.yaml)
CONFIG=config/repos.yaml ./scripts/clone-local.sh

# Custom destination (default: ./mirrors)
OWNER=qte77 DEST=~/backups/github ./scripts/clone-local.sh

# Show usage
./scripts/clone-local.sh --help
```

| Env var | Default | Purpose |
|---|---|---|
| `OWNER` | unset | GitHub user/org → `gh repo list` (mutually exclusive with `CONFIG`) |
| `CONFIG` | `config/repos.yaml` | Curated YAML list (when `OWNER` is unset) |
| `DEST` | `./mirrors` | Local directory for the bare repo clones |
| `VISIBILITY` | unset | Pass-through to `gh repo list --visibility` |
| `LIMIT` | `1000` | Pass-through to `gh repo list --limit` |

Requires `git` and `gh` (authenticated for private repos).
