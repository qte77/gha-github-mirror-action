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
  # Reason: also clear the third target pair, source-auth, shim, and GHA-context
  # vars mirror.sh now reads — CI runs bats with GITHUB_ACTIONS=true, so this must
  # be unset here or the add-mask / self-clobber-guard tests below would leak into
  # every other test.
  unset SOURCE_PAT GH_TARGET_URL GH_TARGET_PAT GIT_SHIM_FAIL GITHUB_ACTIONS \
    GITHUB_SERVER_URL GITHUB_REPOSITORY
}

teardown() {
  # Reason: fixture dirs are named "<prefix>-$BATS_TEST_NUMBER" with no cleanup;
  # without this, a second local run collides with the first run's leftovers
  # ("destination path already exists") even though nothing is actually wrong.
  rm -rf "$TMPDIR"/test-*-"$BATS_TEST_NUMBER" "$TMPDIR"/nonexistent-*-"$BATS_TEST_NUMBER" \
    "$TMPDIR"/fake-target-"$BATS_TEST_NUMBER" "$TMPDIR"/git-shim-"$BATS_TEST_NUMBER" \
    "$TMPDIR"/git-shim-"$BATS_TEST_NUMBER".log 2>/dev/null || true
}

# Reason: opt-in per-test fake `git` — never wired into setup()/_stubs/, since
# setup() seeds fixture repos with real git. Prepends a stub `git` onto PATH that
# logs every invocation's argv (so a test can assert exactly what mirror.sh ran,
# including a credentialed URL that must never reach real git or the network) and
# can simulate a failure on a chosen subcommand via GIT_SHIM_FAIL.
_use_git_shim() {
  local shim_dir="$TMPDIR/git-shim-$BATS_TEST_NUMBER"
  mkdir -p "$shim_dir"
  export GIT_SHIM_LOG="$TMPDIR/git-shim-$BATS_TEST_NUMBER.log"
  : > "$GIT_SHIM_LOG"
  cat > "$shim_dir/git" <<'SHIM'
#!/bin/bash
echo "$@" >> "$GIT_SHIM_LOG"
# Reason: find the subcommand by skipping option flags, including the value that
# follows -c/-C, so `-c credential.helper= clone ...` and `-C dir push ...` are
# both recognized as "clone"/"push" rather than as their preceding flag's value.
subcommand=""
skip_next=false
for arg in "$@"; do
  if $skip_next; then
    skip_next=false
    continue
  fi
  case "$arg" in
    -c|-C) skip_next=true ;;
    -*) ;;
    *) subcommand="$arg"; break ;;
  esac
done
if [ -n "${GIT_SHIM_FAIL:-}" ] && [ "$GIT_SHIM_FAIL" = "$subcommand" ]; then
  echo "fatal: simulated failure: $*" >&2
  exit 128
fi
if [ "$subcommand" = "clone" ]; then
  mkdir -p "${@: -1}"
fi
exit 0
SHIM
  chmod +x "$shim_dir/git"
  export PATH="$shim_dir:$PATH"
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

@test "rejects a PAT containing characters outside [A-Za-z0-9_-]" {
  export SOURCE_REPO="$TMPDIR/test-source-$BATS_TEST_NUMBER"
  export GITLAB_URL="https://gitlab.com/a/r.git"
  export GITLAB_PAT="bad;pat"
  run "$MIRROR_SH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GITLAB_PAT"* ]]
  [[ "$output" == *"invalid"* ]] || [[ "$output" == *"Invalid"* ]]
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

@test "leaves no clone dir behind when clone fails" {
  # Reason: regression guard for the `trap ... EXIT` cleanup — run against a fresh,
  # otherwise-empty TMPDIR so a leftover mirror-repo-* dir is unambiguous.
  local fresh_tmpdir="$TMPDIR/test9-fresh-$BATS_TEST_NUMBER"
  mkdir -p "$fresh_tmpdir"
  export TMPDIR="$fresh_tmpdir"
  export SOURCE_REPO="$TMPDIR/nonexistent-repo-$BATS_TEST_NUMBER"
  export GITLAB_URL="$TMPDIR/fake-target-$BATS_TEST_NUMBER"
  export GITLAB_PAT="fake"
  run "$MIRROR_SH"
  [ "$status" -eq 2 ]
  local leftover_count
  leftover_count=$(find "$TMPDIR" -maxdepth 1 -name 'mirror-repo-*' | wc -l)
  [ "$leftover_count" -eq 0 ]
  rm -rf "$fresh_tmpdir"
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

# --- GitHub target ---

@test "fails when github URL set without PAT" {
  export SOURCE_REPO="$TMPDIR/nonexistent-github-url-$BATS_TEST_NUMBER"
  export GITLAB_URL="$TMPDIR/gitlab-target-$BATS_TEST_NUMBER"
  export GITLAB_PAT="fake"
  export GH_TARGET_URL="https://github.com/t/o.git"
  export GH_TARGET_PAT=""
  run "$MIRROR_SH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GH_TARGET_PAT"* ]]
}

@test "fails when github PAT set without URL" {
  export SOURCE_REPO="$TMPDIR/nonexistent-github-pat-$BATS_TEST_NUMBER"
  export GITLAB_URL="$TMPDIR/gitlab-target-$BATS_TEST_NUMBER"
  export GITLAB_PAT="fake"
  export GH_TARGET_PAT="fake"
  export GH_TARGET_URL=""
  run "$MIRROR_SH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GH_TARGET_URL"* ]]
}

@test "pushes --mirror to github target" {
  local src_repo="$TMPDIR/test-push-gh-src-$BATS_TEST_NUMBER"
  local target_repo="$TMPDIR/test-push-gh-$BATS_TEST_NUMBER"
  mkdir -p "$src_repo" && git -C "$src_repo" init --bare
  mkdir -p "$target_repo" && git -C "$target_repo" init --bare
  local work="$TMPDIR/test-push-gh-work-$BATS_TEST_NUMBER"
  git clone "$src_repo" "$work"
  git -C "$work" commit --allow-empty -m "init"
  git -C "$work" push origin main 2>/dev/null || git -C "$work" push origin master 2>/dev/null

  export SOURCE_REPO="$src_repo"
  # Reason: use local bare repo as target to test push without network
  export GH_TARGET_URL="$target_repo"
  export GH_TARGET_PAT="fake"
  run "$MIRROR_SH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GitHub"* ]]
  local commit_count
  commit_count=$(git -C "$target_repo" rev-list --count --all)
  [ "$commit_count" -ge 1 ]
}

# --- Source auth + credential scrubbing ---

@test "injects source PAT into https clone URL, then scrubs the credential from disk" {
  _use_git_shim
  export SOURCE_REPO="https://gitlab.com/a/r.git"
  export SOURCE_PAT="glpat-src-secret"
  export GITLAB_URL="$TMPDIR/gitlab-target-$BATS_TEST_NUMBER"
  export GITLAB_PAT="fake"
  run "$MIRROR_SH"
  [ "$status" -eq 0 ]
  local log
  log=$(cat "$GIT_SHIM_LOG")
  # Reason: the credentialed clone must be followed by a remote set-url that
  # rewrites origin back to the uncredentialed SOURCE_REPO, so the credential
  # doesn't sit in $CLONE_DIR/config for the rest of the run.
  [[ "$log" == *"clone --bare https://x:glpat-src-secret@gitlab.com/a/r.git"*"remote set-url origin https://gitlab.com/a/r.git"* ]]
  [[ "$output" != *"glpat-src-secret"* ]]
}

@test "scrubs source PAT from clone failure output" {
  _use_git_shim
  export GIT_SHIM_FAIL="clone"
  export SOURCE_REPO="https://gitlab.com/a/r.git"
  export SOURCE_PAT="glpat-src-secret"
  export GITLAB_URL="$TMPDIR/gitlab-target-$BATS_TEST_NUMBER"
  export GITLAB_PAT="fake"
  run "$MIRROR_SH"
  [ "$status" -eq 2 ]
  [[ "$output" == *"***"* ]]
  [[ "$output" == *"Failed to clone https://gitlab.com/a/r.git"* ]]
  [[ "$output" != *"glpat-src-secret"* ]]
}

@test "injects github PAT into https push URL and scrubs failure the same argv-safe way" {
  _use_git_shim
  export GIT_SHIM_FAIL="push"
  export SOURCE_REPO="$TMPDIR/plain-source-$BATS_TEST_NUMBER"
  export GH_TARGET_URL="https://github.com/o/r.git"
  export GH_TARGET_PAT="ghp-supersecret"
  run "$MIRROR_SH"
  [ "$status" -eq 2 ]
  local log
  log=$(cat "$GIT_SHIM_LOG")
  [[ "$log" == *"push --mirror https://x:ghp-supersecret@github.com/o/r.git"* ]]
  [[ "$output" == *"***"* ]]
  [[ "$output" == *"Failed to push to GitHub"* ]]
  [[ "$output" != *"ghp-supersecret"* ]]
}

# --- Self-clobber guard ---

@test "refuses to mirror into the repo running the action" {
  export GITHUB_ACTIONS="true"
  export GITHUB_SERVER_URL="https://github.com"
  export GITHUB_REPOSITORY="Me/Hub"
  # Reason: guard must fire before clone — a nonexistent source proves it never
  # gets that far.
  export SOURCE_REPO="$TMPDIR/nonexistent-guard-$BATS_TEST_NUMBER"
  export GITLAB_URL="$TMPDIR/gitlab-target-$BATS_TEST_NUMBER"
  export GITLAB_PAT="fake"
  # Reason: mixed case + trailing .git proves the guard normalises before comparing.
  export GH_TARGET_URL="https://github.com/me/hub.git"
  export GH_TARGET_PAT="fake"
  run "$MIRROR_SH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Refusing"* ]]
}

# --- Masking ---

@test "emits add-mask with the real PAT when running in GHA" {
  export GITHUB_ACTIONS="true"
  local src_repo="$TMPDIR/test-mask-src-$BATS_TEST_NUMBER"
  local target_repo="$TMPDIR/test-mask-gl-$BATS_TEST_NUMBER"
  mkdir -p "$src_repo" && git -C "$src_repo" init --bare
  mkdir -p "$target_repo" && git -C "$target_repo" init --bare
  local work="$TMPDIR/test-mask-work-$BATS_TEST_NUMBER"
  git clone "$src_repo" "$work"
  git -C "$work" commit --allow-empty -m "init"
  git -C "$work" push origin main 2>/dev/null || git -C "$work" push origin master 2>/dev/null

  export SOURCE_REPO="$src_repo"
  export GITLAB_URL="$target_repo"
  export GITLAB_PAT="glpat-mask-me"
  run "$MIRROR_SH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::add-mask::glpat-mask-me"* ]]
  # Reason: the add-mask line itself carries the real PAT (the runner only masks
  # from that point on); everywhere else it must already be scrubbed to ***.
  local rest="${output/"::add-mask::glpat-mask-me"/}"
  [[ "$rest" != *"glpat-mask-me"* ]]
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
