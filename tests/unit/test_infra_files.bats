#!/usr/bin/env bats

# Infrastructure meta-tests: verify required repo files exist with correct structure.
# Adapted from gha-cross-repo-issue-sync/tests/unit/test_infra_files.bats

REPO_ROOT="$BATS_TEST_DIRNAME/../.."

setup() {
  export TMPDIR="${BATS_TMPDIR:-/tmp/claude-1000/bats-tmp}"
}

# --- action.yaml ---

@test "action.yaml exists and has required branding fields" {
  [ -f "$REPO_ROOT/action.yaml" ]
  grep -q "^name:" "$REPO_ROOT/action.yaml"
  grep -q "^description:" "$REPO_ROOT/action.yaml"
  grep -q "icon:" "$REPO_ROOT/action.yaml"
  grep -q "color:" "$REPO_ROOT/action.yaml"
}

@test "action.yaml unsets GITHUB_TOKEN so PAT takes precedence" {
  # Reason: gh CLI resolves GITHUB_TOKEN > GH_TOKEN; must unset in GHA
  grep -q "GITHUB_TOKEN: ''" "$REPO_ROOT/action.yaml"
}

@test "action.yaml has source_repo input for central hub mode" {
  grep -q "source_repo" "$REPO_ROOT/action.yaml"
}

# --- mirror script ---

@test "mirror.sh exists and is executable" {
  [ -f "$REPO_ROOT/scripts/mirror.sh" ]
  [ -x "$REPO_ROOT/scripts/mirror.sh" ]
}

# --- config ---

@test "config/repos.yaml exists for central hub" {
  [ -f "$REPO_ROOT/config/repos.yaml" ]
}

# --- dependabot ---

@test "dependabot.yml exists and covers github-actions ecosystem" {
  [ -f "$REPO_ROOT/.github/dependabot.yml" ]
  grep -q "github-actions" "$REPO_ROOT/.github/dependabot.yml"
}

# --- workflows ---

@test "mirror-all workflow exists with schedule trigger" {
  [ -f "$REPO_ROOT/.github/workflows/mirror-all.yaml" ]
  grep -q "schedule" "$REPO_ROOT/.github/workflows/mirror-all.yaml"
}

@test "bump-and-release workflow exists with bump-my-version" {
  [ -f "$REPO_ROOT/.github/workflows/bump-and-release.yaml" ]
  grep -q "bump-my-version" "$REPO_ROOT/.github/workflows/bump-and-release.yaml"
}

@test "codeql workflow exists" {
  [ -f "$REPO_ROOT/.github/workflows/codeql.yaml" ]
}

@test "test workflow runs bats" {
  [ -f "$REPO_ROOT/.github/workflows/test.yaml" ]
  grep -q "bats" "$REPO_ROOT/.github/workflows/test.yaml"
}

@test "integration workflow exists and uses local action" {
  [ -f "$REPO_ROOT/.github/workflows/integration.yaml" ]
  grep -q "uses: ./" "$REPO_ROOT/.github/workflows/integration.yaml"
}

# --- cleanup script ---

@test "cleanup script exists and is executable" {
  [ -f "$REPO_ROOT/.github/scripts/delete_branch_pr_tag.sh" ]
  [ -x "$REPO_ROOT/.github/scripts/delete_branch_pr_tag.sh" ]
}

# --- bumpversion ---

@test "pyproject.toml has bumpversion config" {
  [ -f "$REPO_ROOT/pyproject.toml" ]
  grep -q "tool.bumpversion" "$REPO_ROOT/pyproject.toml"
}

# --- .gitmessage ---

@test ".gitmessage exists with conventional commit hint" {
  [ -f "$REPO_ROOT/.gitmessage" ]
  grep -qi "feat\|fix\|chore\|docs" "$REPO_ROOT/.gitmessage"
}

# --- templates ---

@test "PR template exists" {
  [ -f "$REPO_ROOT/.github/pull_request_template.md" ]
}

# --- LICENSE ---

@test "LICENSE exists with Apache-2.0" {
  [ -f "$REPO_ROOT/LICENSE" ]
  grep -q "Apache License" "$REPO_ROOT/LICENSE"
}
