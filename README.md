# gha-github-mirror-action

Mirror GitHub repositories to GitLab and/or Codeberg. All branches, tags, and refs.

[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.1.0-blue)](CHANGELOG.md)
[![mirror-all](https://github.com/qte77/gha-github-mirror-action/actions/workflows/mirror-all.yaml/badge.svg)](https://github.com/qte77/gha-github-mirror-action/actions/workflows/mirror-all.yaml)
[![BATS](https://github.com/qte77/gha-github-mirror-action/actions/workflows/test.yaml/badge.svg)](https://github.com/qte77/gha-github-mirror-action/actions/workflows/test.yaml)
[![CodeFactor](https://www.codefactor.io/repository/github/qte77/gha-github-mirror-action/badge)](https://www.codefactor.io/repository/github/qte77/gha-github-mirror-action)
[![CodeQL](https://github.com/qte77/gha-github-mirror-action/actions/workflows/codeql.yaml/badge.svg)](https://github.com/qte77/gha-github-mirror-action/actions/workflows/codeql.yaml)
[![Dependabot](https://github.com/qte77/gha-github-mirror-action/actions/workflows/dependabot/dependabot-updates/badge.svg)](https://github.com/qte77/gha-github-mirror-action/actions/workflows/dependabot/dependabot-updates)

## What

- Runs as a marketplace action for a single repo, a central hub mirroring many repos on a schedule, or a local script for offline backups
- Validates that at least one target (URL + PAT pair) is configured
- Masks every configured PAT in CI logs via GitHub's `::add-mask::`, emitted before any output
- Clones the source repository as a bare repo, optionally authenticated via `source_pat`
- Pushes `--mirror` to each configured target (GitLab, Codeberg, and/or GitHub)
- Scrubs captured output as a defense-in-depth measure, and clears the credentialed URL from the clone's on-disk git config
- Cleans up the temporary clone directory

## How

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
`push --mirror` mechanics (see [What](#what)) — only the source and target change.

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

### Inputs

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

At least one target (URL + PAT pair) must be configured. For central-hub scheduling across many
repos and the local-clone script (no GitHub Actions, no PATs required), see
[docs/usage.md](docs/usage.md).

## Why

A `git clone --mirror` + cron script uses the same git primitives but needs its own always-on
host, secret storage, and someone to notice when it silently stops. This action runs inside GitHub
Actions you already have: PATs live in encrypted secrets, a failed run is a red check, and one
workflow mirrors a single repo or fans out to many from a scheduled hub — no separate
infrastructure.

## Refs

- [CHANGELOG](CHANGELOG.md)
- [CONTRIBUTING](CONTRIBUTING.md)
- [Usage details](docs/usage.md)

## License

[Apache-2.0](LICENSE)
