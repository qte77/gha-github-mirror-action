# gha-github-mirror-action

Mirror GitHub repositories to GitLab and/or Codeberg. All branches, tags, and refs.

![Version](https://img.shields.io/badge/version-0.1.0-8A2BE2)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)
[![mirror-all](https://github.com/qte77/gha-github-mirror-action/actions/workflows/mirror-all.yaml/badge.svg)](https://github.com/qte77/gha-github-mirror-action/actions/workflows/mirror-all.yaml)
[![BATS](https://github.com/qte77/gha-github-mirror-action/actions/workflows/test.yaml/badge.svg)](https://github.com/qte77/gha-github-mirror-action/actions/workflows/test.yaml)
[![CodeFactor](https://www.codefactor.io/repository/github/qte77/gha-github-mirror-action/badge)](https://www.codefactor.io/repository/github/qte77/gha-github-mirror-action)
[![CodeQL](https://github.com/qte77/gha-github-mirror-action/actions/workflows/codeql.yaml/badge.svg)](https://github.com/qte77/gha-github-mirror-action/actions/workflows/codeql.yaml)
[![Dependabot](https://github.com/qte77/gha-github-mirror-action/actions/workflows/dependabot/dependabot-updates/badge.svg)](https://github.com/qte77/gha-github-mirror-action/actions/workflows/dependabot/dependabot-updates)

**Multi-mode**: marketplace action for a single repo, central hub mirroring many on a schedule, or local script for offline backups.

For version history have a look at the [CHANGELOG](CHANGELOG.md).

## Usage

### Per-repo (marketplace action)

```yaml
name: Mirror
on: [push, create, delete]
jobs:
  mirror:
    runs-on: ubuntu-latest
    steps:
      - uses: qte77/gha-github-mirror-action@v0
        with:
          gitlab_url: https://gitlab.com/org/repo.git
          gitlab_pat: ${{ secrets.GITLAB_PAT }}
          codeberg_url: https://codeberg.org/org/repo.git
          codeberg_pat: ${{ secrets.CODEBERG_PAT }}
```

### Modes

The action supports three mirroring shapes, chosen by which inputs are set. All three share the same
`push --mirror` mechanics (see [What it does](#what-it-does)) — only the source and target change.

**Push** (default, shown above) — mirror the current repo out to GitLab and/or Codeberg. No source
credential needed for a public source; GitHub is read without a PAT.

**Invert / pull** — mirror *from* a repo on another host *into* a GitHub repo the workflow's account
controls. Needs `source_pat` to read the non-GitHub source and `github_url`/`github_pat` to write the
GitHub target:

```yaml
      - uses: qte77/gha-github-mirror-action@v0
        with:
          source_repo: https://gitlab.com/other-org/other-repo.git
          source_pat: ${{ secrets.GITLAB_PAT }}
          github_url: https://github.com/org/backup-repo.git
          github_pat: ${{ secrets.GH_TARGET_PAT }}
```

**Router** — the repo running the workflow is neither source nor target; it only supplies compute
(e.g. GitLab account A → Codeberg account B). Credential both directions explicitly:

```yaml
      - uses: qte77/gha-github-mirror-action@v0
        with:
          source_repo: https://gitlab.com/org-a/repo.git
          source_pat: ${{ secrets.GITLAB_PAT }}
          codeberg_url: https://codeberg.org/org-b/repo.git
          codeberg_pat: ${{ secrets.CODEBERG_PAT }}
```

> `source_pat`, `github_url`, and `github_pat` ship in `v0.2.0`; the floating `@v0` tag picks them up
> once that release is tagged — see the [CHANGELOG](CHANGELOG.md).

**Before using an invert or router target:**

- The GitHub target repo must **pre-exist and be unprotected** — `git push --mirror` force-updates
  and deletes refs to match the source exactly, and fails against branch protection/rulesets.
- The self-clobber guard (refuses to mirror into the repo running the action) **only covers
  `https://`-form self-targets**; `ssh://`/`git@host:path` self-targets are not detected.
- [`config/repos.yaml`](config/repos.yaml) is a **trust boundary**: anyone who can merge a change to
  it can point any configured PAT at any URL listed as a `source`.

### Central hub (schedule + dispatch)

The repo includes a `mirror-all.yaml` workflow that reads `config/repos.yaml` and mirrors all listed repos via matrix jobs.

### Local clone (script-only)

Mirror GitHub repos to a local directory using just `scripts/clone-local.sh` — no GitHub Actions, no PATs, no GitLab/Codeberg. Bare `--mirror` clones; idempotent re-runs (auto-prune deletions on subsequent fetches).

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

## What it does

1. Validates that at least one target (URL + PAT pair) is configured
2. Masks every configured PAT in CI logs via GitHub's `::add-mask::`, emitted before any output
3. Clones the source repository as a bare repo (optionally authenticated via `source_pat`)
4. Pushes `--mirror` to each configured target (GitLab, Codeberg, and/or GitHub)
5. Scrubs captured command output as a defense-in-depth measure, and clears the credentialed URL
   from the clone's on-disk git config
6. Cleans up the temporary clone directory

## Inputs

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `source_repo` | No | Current repo | Source repo URL |
| `source_pat` | No | | PAT for the source repo, when it requires authentication (e.g. a private repo, or a non-GitHub source) |
| `gitlab_url` | No | | Target GitLab repo HTTPS URL |
| `gitlab_pat` | No | | GitLab PAT (`write_repository` scope) |
| `codeberg_url` | No | | Target Codeberg repo HTTPS URL |
| `codeberg_pat` | No | | Codeberg PAT (repo write scope) |
| `github_url` | No | | Target GitHub repo HTTPS URL; must not be the repo running the action |
| `github_pat` | No | | GitHub PAT for the target repo (`contents: read+write` scope) |

At least one target (URL + PAT pair) must be configured.

## Development

```bash
# Run tests
bats tests/unit/

# Lint shell scripts (shellcheck ships preinstalled on ubuntu-latest CI runners)
shellcheck scripts/*.sh .github/scripts/*.sh

# Lint workflow files (actionlint is not preinstalled; install locally first, e.g.
# via https://github.com/rhysd/actionlint/blob/main/docs/install.md)
actionlint
```

## License

[Apache-2.0](LICENSE)
