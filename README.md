# gha-github-mirror-action

Mirror GitHub repositories to GitLab and/or Codeberg. All branches, tags, and refs.

![Version](https://img.shields.io/badge/version-0.1.0-8A2BE2)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![mirror-all](https://github.com/qte77/gha-github-mirror-action/actions/workflows/mirror-all.yaml/badge.svg)](https://github.com/qte77/gha-github-mirror-action/actions/workflows/mirror-all.yaml)
[![CodeQL](https://github.com/qte77/gha-github-mirror-action/actions/workflows/codeql.yaml/badge.svg)](https://github.com/qte77/gha-github-mirror-action/actions/workflows/codeql.yaml)
[![Dependabot](https://github.com/qte77/gha-github-mirror-action/actions/workflows/dependabot/dependabot-updates/badge.svg)](https://github.com/qte77/gha-github-mirror-action/actions/workflows/dependabot/dependabot-updates)
[![Tests](https://github.com/qte77/gha-github-mirror-action/actions/workflows/test.yml/badge.svg)](https://github.com/qte77/gha-github-mirror-action/actions/workflows/test.yml)

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

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `source_repo` | Source repo URL | No | Current repo |
| `gitlab_url` | Target GitLab repo HTTPS URL | No | |
| `gitlab_pat` | GitLab PAT (`write_repository` scope) | No | |
| `codeberg_url` | Target Codeberg repo HTTPS URL | No | |
| `codeberg_pat` | Codeberg PAT (repo write scope) | No | |

At least one target (URL + PAT pair) must be configured.

## Development

```bash
# Run tests
bats tests/unit/
```

## License

[Apache-2.0](LICENSE)
