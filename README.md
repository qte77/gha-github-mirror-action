# gha-github-mirror-action

Mirror GitHub repositories to GitLab and/or Codeberg. All branches, tags, and refs.

[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.1.0-blue)](CHANGELOG.md)
[![mirror-all](https://github.com/qte77/gha-github-mirror-action/actions/workflows/mirror-all.yaml/badge.svg)](https://github.com/qte77/gha-github-mirror-action/actions/workflows/mirror-all.yaml)
[![BATS](https://github.com/qte77/gha-github-mirror-action/actions/workflows/test.yaml/badge.svg)](https://github.com/qte77/gha-github-mirror-action/actions/workflows/test.yaml)
[![CodeFactor](https://www.codefactor.io/repository/github/qte77/gha-github-mirror-action/badge)](https://www.codefactor.io/repository/github/qte77/gha-github-mirror-action)
[![CodeQL](https://github.com/qte77/gha-github-mirror-action/actions/workflows/codeql.yaml/badge.svg)](https://github.com/qte77/gha-github-mirror-action/actions/workflows/codeql.yaml)
[![Dependabot](https://github.com/qte77/gha-github-mirror-action/actions/workflows/dependabot/dependabot-updates/badge.svg)](https://github.com/qte77/gha-github-mirror-action/actions/workflows/dependabot/dependabot-updates)

## What

- Runs as a marketplace action for a single repo, a central hub mirroring many repos on a schedule, or a local script for offline backups
- Validates that at least one target (URL + PAT pair) is configured
- Masks all PATs in CI logs to prevent credential leaks
- Clones the source repository as a bare repo
- Pushes `--mirror` to each configured target (GitLab and/or Codeberg)
- Scrubs PATs from all output as a defense-in-depth measure
- Cleans up the temporary clone directory

## How

```yaml
name: Mirror
on: [push, create, delete]
jobs:
  mirror:
    runs-on: ubuntu-latest
    steps:
      - uses: qte77/gha-github-mirror-action@v1
        with:
          gitlab_url: https://gitlab.com/org/repo.git
          gitlab_pat: ${{ secrets.GITLAB_PAT }}
          codeberg_url: https://codeberg.org/org/repo.git
          codeberg_pat: ${{ secrets.CODEBERG_PAT }}
```

### Inputs

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `source_repo` | No | Current repo | Source repo URL |
| `gitlab_url` | No | | Target GitLab repo HTTPS URL |
| `gitlab_pat` | No | | GitLab PAT (`write_repository` scope) |
| `codeberg_url` | No | | Target Codeberg repo HTTPS URL |
| `codeberg_pat` | No | | Codeberg PAT (repo write scope) |

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
