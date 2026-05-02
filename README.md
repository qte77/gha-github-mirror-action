# gha-github-mirror-action

Mirror GitHub repositories to GitLab and/or Codeberg. All branches, tags, and refs.

![Version](https://img.shields.io/badge/version-0.1.0-8A2BE2)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![mirror-all](https://github.com/qte77/gha-github-mirror-action/actions/workflows/mirror-all.yaml/badge.svg)](https://github.com/qte77/gha-github-mirror-action/actions/workflows/mirror-all.yaml)
[![BATS](https://github.com/qte77/gha-github-mirror-action/actions/workflows/test.yaml/badge.svg)](https://github.com/qte77/gha-github-mirror-action/actions/workflows/test.yaml)
[![CodeFactor](https://www.codefactor.io/repository/github/qte77/gha-github-mirror-action/badge)](https://www.codefactor.io/repository/github/qte77/gha-github-mirror-action)
[![CodeQL](https://github.com/qte77/gha-github-mirror-action/actions/workflows/codeql.yaml/badge.svg)](https://github.com/qte77/gha-github-mirror-action/actions/workflows/codeql.yaml)
[![Dependabot](https://github.com/qte77/gha-github-mirror-action/actions/workflows/dependabot/dependabot-updates/badge.svg)](https://github.com/qte77/gha-github-mirror-action/actions/workflows/dependabot/dependabot-updates)

**Dual-mode**: Use as a marketplace action in any repo, or as a central hub mirroring all repos on a schedule.

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
      - uses: qte77/gha-github-mirror-action@v1
        with:
          gitlab_url: https://gitlab.com/org/repo.git
          gitlab_pat: ${{ secrets.GITLAB_PAT }}
          codeberg_url: https://codeberg.org/org/repo.git
          codeberg_pat: ${{ secrets.CODEBERG_PAT }}
```

### Central hub (schedule + dispatch)

The repo includes a `mirror-all.yaml` workflow that reads `config/repos.yaml` and mirrors all listed repos via matrix jobs.

## What it does

1. Validates that at least one target (URL + PAT pair) is configured
2. Masks all PATs in CI logs to prevent credential leaks
3. Clones the source repository as a bare repo
4. Pushes `--mirror` to each configured target (GitLab and/or Codeberg)
5. Scrubs PATs from all output as a defense-in-depth measure
6. Cleans up the temporary clone directory

## Inputs

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `source_repo` | No | Current repo | Source repo URL |
| `gitlab_url` | No | | Target GitLab repo HTTPS URL |
| `gitlab_pat` | No | | GitLab PAT (`write_repository` scope) |
| `codeberg_url` | No | | Target Codeberg repo HTTPS URL |
| `codeberg_pat` | No | | Codeberg PAT (repo write scope) |

At least one target (URL + PAT pair) must be configured.

## Development

```bash
# Run tests
bats tests/unit/
```

## License

[Apache-2.0](LICENSE)
