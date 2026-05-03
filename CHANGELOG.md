# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html), i.e. MAJOR.MINOR.PATCH (Breaking.Feature.Patch).

Types of changes:

- `Added` / `Changed` / `Deprecated` / `Removed` / `Fixed` / `Security`

## [Unreleased]

### Added

- `scripts/clone-local.sh`: clone GitHub repos to a local directory as bare mirrors (`--mirror` first run, fetch on re-run). Supports `OWNER` (via `gh repo list`) or `CONFIG` (curated YAML) modes. See README → Usage → Local clone.
- Core `mirror.sh` script: config validation, bare clone, `--mirror` push to GitLab and/or Codeberg
- PAT masking in CI logs (`::add-mask::` in GHA, sed scrubbing in push output)
- Dual-target support: continues to second target if first push fails
- `action.yaml`: composite action with `source_repo`, gitlab, codeberg inputs
- `mirror-all.yaml`: central hub workflow (schedule + dispatch, matrix from `config/repos.yaml`)
- Infrastructure: bump-and-release, codeql, test (BATS), dependabot, cleanup script
- 29 BATS tests: 16 infra meta-tests + 13 mirror logic tests

---
