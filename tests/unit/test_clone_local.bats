#!/usr/bin/env bats

# Behavioral tests for scripts/clone-local.sh — summary output, exit codes.

CLONE_SH="$BATS_TEST_DIRNAME/../../scripts/clone-local.sh"

setup() {
  export TMPDIR="${BATS_TMPDIR:-/tmp/claude-1000/bats-tmp}"
  git config --global user.name "test"  2>/dev/null || true
  git config --global user.email "test@test" 2>/dev/null || true
  unset OWNER CONFIG DEST VISIBILITY LIMIT
  # Reason: provide a minimal yq stub when the real tool isn't installed
  # (sandboxed/dev environments). Handles only the `-r '.[].source' <file>`
  # pattern the script uses for CONFIG mode.
  if ! command -v yq >/dev/null 2>&1; then
    export PATH="$BATS_TEST_DIRNAME/_stubs:$PATH"
    mkdir -p "$BATS_TEST_DIRNAME/_stubs"
    cat > "$BATS_TEST_DIRNAME/_stubs/yq" <<'STUB'
#!/usr/bin/env bash
# Minimal yq stub: handles `-r '.[].source' <file>` only.
file="${@: -1}"
grep -E '^- source:' "$file" | sed -E 's/^- source: *//; s/"//g'
STUB
    chmod +x "$BATS_TEST_DIRNAME/_stubs/yq"
  fi
}

teardown() {
  rm -rf "$BATS_TEST_DIRNAME/_stubs"
}

# Helper: build a tiny CONFIG with one good (local bare repo) and one bad source.
_make_config() {
  local n="$1"
  local good_src="$TMPDIR/clone-good-src-$n"
  local bad_src="https://example.invalid/nonexistent-${n}.git"
  git init --bare "$good_src" >/dev/null
  printf -- '- source: %s\n- source: %s\n' "$good_src" "$bad_src" \
    > "$TMPDIR/clone-config-$n.yaml"
  echo "$TMPDIR/clone-config-$n.yaml"
}

@test "prints summary with succeeded and failed counts" {
  cfg=$(_make_config 1)
  export CONFIG="$cfg"
  export DEST="$TMPDIR/clone-dest-1"
  run "$CLONE_SH"
  [[ "$output" == *"=== Summary ==="* ]]
  [[ "$output" == *"Succeeded: 1"* ]]
  [[ "$output" == *"Failed:    1"* ]] || [[ "$output" == *"Failed: 1"* ]]
}

@test "lists names of failed repos in summary" {
  cfg=$(_make_config 2)
  export CONFIG="$cfg"
  export DEST="$TMPDIR/clone-dest-2"
  run "$CLONE_SH"
  [[ "$output" == *"Failed repos:"* ]]
  [[ "$output" == *"nonexistent-2"* ]]
}

@test "exits non-zero when any repo fails" {
  cfg=$(_make_config 3)
  export CONFIG="$cfg"
  export DEST="$TMPDIR/clone-dest-3"
  run "$CLONE_SH"
  [ "$status" -ne 0 ]
}

@test "exits zero when all repos succeed" {
  good_src="$TMPDIR/clone-good-only-src-4"
  git init --bare "$good_src" >/dev/null
  cfg="$TMPDIR/clone-config-4.yaml"
  printf -- '- source: %s\n' "$good_src" > "$cfg"
  export CONFIG="$cfg"
  export DEST="$TMPDIR/clone-dest-4"
  run "$CLONE_SH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Succeeded: 1"* ]]
  [[ "$output" == *"Failed:    0"* ]] || [[ "$output" == *"Failed: 0"* ]]
}
