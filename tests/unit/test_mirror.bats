#!/usr/bin/env bats

# Tests for scripts/mirror.sh — config validation, clone, push, security.

MIRROR_SH="$BATS_TEST_DIRNAME/../../scripts/mirror.sh"

setup() {
  export TMPDIR="${BATS_TMPDIR:-/tmp/claude-1000/bats-tmp}"
  # Clear all env vars mirror.sh reads
  unset SOURCE_REPO GITLAB_URL GITLAB_PAT CODEBERG_URL CODEBERG_PAT
}

# --- Config validation ---

@test "fails when no targets configured" {
  export SOURCE_REPO="https://github.com/test/repo.git"
  run "$MIRROR_SH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no target"* ]] || [[ "$output" == *"No target"* ]]
}

@test "fails when gitlab URL set without PAT" {
  export SOURCE_REPO="https://github.com/test/repo.git"
  export GITLAB_URL="https://gitlab.com/test/repo.git"
  export GITLAB_PAT=""
  run "$MIRROR_SH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PAT"* ]] || [[ "$output" == *"pat"* ]] || [[ "$output" == *"token"* ]]
}

@test "fails when gitlab PAT set without URL" {
  export SOURCE_REPO="https://github.com/test/repo.git"
  export GITLAB_PAT="glpat-fake123"
  export GITLAB_URL=""
  run "$MIRROR_SH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"URL"* ]] || [[ "$output" == *"url"* ]]
}

@test "fails when codeberg URL set without PAT" {
  export SOURCE_REPO="https://github.com/test/repo.git"
  export CODEBERG_URL="https://codeberg.org/test/repo.git"
  export CODEBERG_PAT=""
  run "$MIRROR_SH"
  [ "$status" -eq 1 ]
}

@test "fails when codeberg PAT set without URL" {
  export SOURCE_REPO="https://github.com/test/repo.git"
  export CODEBERG_PAT="fake-cb-token"
  export CODEBERG_URL=""
  run "$MIRROR_SH"
  [ "$status" -eq 1 ]
}

@test "fails when source repo not set" {
  export GITLAB_URL="https://gitlab.com/test/repo.git"
  export GITLAB_PAT="glpat-fake123"
  export SOURCE_REPO=""
  run "$MIRROR_SH"
  [ "$status" -eq 1 ]
}
