#!/usr/bin/env bats

# Tests for scripts/mirror.sh — config validation, clone, push, security.

MIRROR_SH="$BATS_TEST_DIRNAME/../../scripts/mirror.sh"

setup() {
  export TMPDIR="${BATS_TMPDIR:-/tmp/claude-1000/bats-tmp}"
  # Reason: CI runners (and a dev machine) may lack git identity, or have a real
  # one that must not be touched; set it via env vars scoped to this test
  # process only — never `git config --global`, which mutates the real
  # developer's identity on disk and races with other test processes running
  # in parallel worktrees.
  export GIT_AUTHOR_NAME="test" GIT_AUTHOR_EMAIL="test@test"
  export GIT_COMMITTER_NAME="test" GIT_COMMITTER_EMAIL="test@test"
  # Reason: a machine with global commit signing enabled (gpgsign=true) rejects
  # commits from this fake identity; force-disable signing for every git call
  # this test process (and the mirror.sh subprocesses it spawns) makes, without
  # touching the real global config.
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
  # Clear all env vars mirror.sh reads
  unset SOURCE_REPO GITLAB_URL GITLAB_PAT CODEBERG_URL CODEBERG_PAT
}

teardown() {
  # Reason: fixture dirs are named "<prefix>-$BATS_TEST_NUMBER" with no cleanup;
  # without this, a second local run collides with the first run's leftovers
  # ("destination path already exists") even though nothing is actually wrong.
  rm -rf "$TMPDIR"/test-*-"$BATS_TEST_NUMBER" "$TMPDIR"/nonexistent-*-"$BATS_TEST_NUMBER" \
    "$TMPDIR"/fake-target-"$BATS_TEST_NUMBER" 2>/dev/null || true
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

# --- Clone operation ---

@test "clones source as bare repo" {
  local src_repo="$TMPDIR/test-source-$BATS_TEST_NUMBER"
  local target_repo="$TMPDIR/test-clone-target-$BATS_TEST_NUMBER"
  mkdir -p "$src_repo" && git -C "$src_repo" init --bare
  mkdir -p "$target_repo" && git -C "$target_repo" init --bare
  local work="$TMPDIR/test-work-$BATS_TEST_NUMBER"
  git clone "$src_repo" "$work"
  git -C "$work" commit --allow-empty -m "init"
  git -C "$work" push origin main 2>/dev/null || git -C "$work" push origin master 2>/dev/null

  export SOURCE_REPO="$src_repo"
  # Reason: use local bare repo as target to avoid network calls
  export GITLAB_URL="$target_repo"
  export GITLAB_PAT="fake"
  run "$MIRROR_SH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cloning"* ]] || [[ "$output" == *"cloning"* ]] || [[ "$output" == *"clone"* ]]
}

@test "fails with exit 2 when clone fails" {
  # Reason: use local nonexistent path to avoid DNS/network hang
  export SOURCE_REPO="$TMPDIR/nonexistent-repo-$BATS_TEST_NUMBER"
  export GITLAB_URL="$TMPDIR/fake-target-$BATS_TEST_NUMBER"
  export GITLAB_PAT="fake"
  run "$MIRROR_SH"
  [ "$status" -eq 2 ]
}

# --- Push operation ---

@test "pushes --mirror to gitlab target" {
  # Setup local source repo
  local src_repo="$TMPDIR/test-push-src-$BATS_TEST_NUMBER"
  local target_repo="$TMPDIR/test-push-gl-$BATS_TEST_NUMBER"
  mkdir -p "$src_repo" && git -C "$src_repo" init --bare
  mkdir -p "$target_repo" && git -C "$target_repo" init --bare
  local work="$TMPDIR/test-push-work-$BATS_TEST_NUMBER"
  git clone "$src_repo" "$work"
  git -C "$work" commit --allow-empty -m "init"
  git -C "$work" push origin main 2>/dev/null || git -C "$work" push origin master 2>/dev/null

  export SOURCE_REPO="$src_repo"
  # Reason: use local bare repo as target to test push without network
  export GITLAB_URL="$target_repo"
  export GITLAB_PAT="fake"
  run "$MIRROR_SH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gitlab"* ]] || [[ "$output" == *"GitLab"* ]]
}

@test "pushes --mirror to codeberg target" {
  local src_repo="$TMPDIR/test-push-src-cb-$BATS_TEST_NUMBER"
  local target_repo="$TMPDIR/test-push-cb-$BATS_TEST_NUMBER"
  mkdir -p "$src_repo" && git -C "$src_repo" init --bare
  mkdir -p "$target_repo" && git -C "$target_repo" init --bare
  local work="$TMPDIR/test-push-work-cb-$BATS_TEST_NUMBER"
  git clone "$src_repo" "$work"
  git -C "$work" commit --allow-empty -m "init"
  git -C "$work" push origin main 2>/dev/null || git -C "$work" push origin master 2>/dev/null

  export SOURCE_REPO="$src_repo"
  export CODEBERG_URL="$target_repo"
  export CODEBERG_PAT="fake"
  run "$MIRROR_SH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"codeberg"* ]] || [[ "$output" == *"Codeberg"* ]]
}

@test "pushes to both targets when both configured" {
  local src_repo="$TMPDIR/test-push-both-src-$BATS_TEST_NUMBER"
  local gl_target="$TMPDIR/test-push-both-gl-$BATS_TEST_NUMBER"
  local cb_target="$TMPDIR/test-push-both-cb-$BATS_TEST_NUMBER"
  mkdir -p "$src_repo" && git -C "$src_repo" init --bare
  mkdir -p "$gl_target" && git -C "$gl_target" init --bare
  mkdir -p "$cb_target" && git -C "$cb_target" init --bare
  local work="$TMPDIR/test-push-both-work-$BATS_TEST_NUMBER"
  git clone "$src_repo" "$work"
  git -C "$work" commit --allow-empty -m "init"
  git -C "$work" push origin main 2>/dev/null || git -C "$work" push origin master 2>/dev/null

  export SOURCE_REPO="$src_repo"
  export GITLAB_URL="$gl_target"
  export GITLAB_PAT="fake"
  export CODEBERG_URL="$cb_target"
  export CODEBERG_PAT="fake"
  run "$MIRROR_SH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GitLab"* ]] || [[ "$output" == *"gitlab"* ]]
  [[ "$output" == *"Codeberg"* ]] || [[ "$output" == *"codeberg"* ]]
}

@test "continues to second target if first push fails" {
  local src_repo="$TMPDIR/test-continue-src-$BATS_TEST_NUMBER"
  local cb_target="$TMPDIR/test-continue-cb-$BATS_TEST_NUMBER"
  mkdir -p "$src_repo" && git -C "$src_repo" init --bare
  mkdir -p "$cb_target" && git -C "$cb_target" init --bare
  local work="$TMPDIR/test-continue-work-$BATS_TEST_NUMBER"
  git clone "$src_repo" "$work"
  git -C "$work" commit --allow-empty -m "init"
  git -C "$work" push origin main 2>/dev/null || git -C "$work" push origin master 2>/dev/null

  export SOURCE_REPO="$src_repo"
  # Reason: first target is nonexistent local path (will fail), second is local bare repo (will succeed)
  export GITLAB_URL="$TMPDIR/nonexistent-push-target-$BATS_TEST_NUMBER"
  export GITLAB_PAT="fake"
  export CODEBERG_URL="$cb_target"
  export CODEBERG_PAT="fake"
  run "$MIRROR_SH"
  # Reason: exit 2 because at least one push failed
  [ "$status" -eq 2 ]
  # But second target should still have been attempted
  [[ "$output" == *"Codeberg"* ]] || [[ "$output" == *"codeberg"* ]]
}

# --- Security ---

@test "PAT not visible in error output" {
  local src_repo="$TMPDIR/test-sec-src-$BATS_TEST_NUMBER"
  mkdir -p "$src_repo" && git -C "$src_repo" init --bare
  local work="$TMPDIR/test-sec-work-$BATS_TEST_NUMBER"
  git clone "$src_repo" "$work"
  git -C "$work" commit --allow-empty -m "init"
  git -C "$work" push origin main 2>/dev/null || git -C "$work" push origin master 2>/dev/null

  export SOURCE_REPO="$src_repo"
  # Reason: use nonexistent local path to trigger push failure without network
  export GITLAB_URL="$TMPDIR/nonexistent-sec-target-$BATS_TEST_NUMBER"
  export GITLAB_PAT="glpat-supersecret123"
  run "$MIRROR_SH"
  # Reason: PAT must never appear in output — could leak in CI logs
  [[ "$output" != *"glpat-supersecret123"* ]]
}
