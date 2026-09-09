# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html), i.e. MAJOR.MINOR.PATCH (Breaking.Feature.Patch).

Types of changes:

- `Added` / `Changed` / `Deprecated` / `Removed` / `Fixed` / `Security`

## [Unreleased]

### Added

- `scripts/clone-local.sh`: clone GitHub repos to a local directory as bare mirrors (`--mirror` first run, fetch on re-run). Supports `OWNER` (via `gh repo list`) or `CONFIG` (curated YAML) modes. See README → Usage → Local clone.
- BATS test suite covering infra meta-tests, `mirror.sh` logic, and `clone-local.sh` behavior (see `tests/unit/`)
- `source_pat` input: authenticates the clone of a private or non-GitHub source
- `github_url`/`github_pat` inputs: mirror into a GitHub target (invert/router modes) as a third `push --mirror` call alongside GitLab/Codeberg. See README → Usage → Modes.
- Self-clobber guard: refuses to mirror into the repo running the action (HTTPS-form targets only)
- Hub: `github` field in `config/repos.yaml`/`mirror-all.yaml` matrix, gating all three PATs on their matching URL being set
- shellcheck + actionlint CI checks for `scripts/*.sh` and `.github/scripts/*.sh`
- Dependabot `groups:` — weekly `github-actions-minor-patch` group for minor/patch updates

### Fixed

- `::add-mask::` now actually masks: previously emitted inside the scrubbed output pipeline, so the runner only ever saw `::add-mask::***` instead of the real PAT
- Hub `mirror-all.yaml` passed every configured PAT unconditionally, even when its target URL was unset; PATs are now gated on their matching URL
- Credential-on-disk residue: the credentialed clone URL no longer lingers in `$CLONE_DIR/config` after cloning, and the temporary clone directory is now cleaned up via a trap that also covers the clone-failure path

---

## [0.1.0] - 2026-03-24

### Added

- Core `mirror.sh` script: config validation, bare clone, `--mirror` push to GitLab and/or Codeberg
- PAT masking in CI logs (`::add-mask::` in GHA, sed scrubbing in push output)
- Dual-target support: continues to second target if first push fails
- `action.yaml`: composite action with `source_repo`, gitlab, codeberg inputs
- `mirror-all.yaml`: central hub workflow (schedule + dispatch, matrix from `config/repos.yaml`)
- Infrastructure: bump-and-release, codeql, test (BATS), dependabot, cleanup script
- 29 BATS tests: 16 infra meta-tests + 13 mirror logic tests

---
