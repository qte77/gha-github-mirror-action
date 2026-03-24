#!/bin/bash
# Mirror a GitHub repo to GitLab and/or Codeberg.
# Called by action.yaml; expects env vars: SOURCE_REPO, GITLAB_URL, GITLAB_PAT,
# CODEBERG_URL, CODEBERG_PAT.
# Exit codes: 0 = success, 1 = config error, 2 = git error

# Reason: no set -e — we handle errors explicitly to continue pushing to remaining targets
set -uo pipefail

# --- Config validation ---

if [ -z "${SOURCE_REPO:-}" ]; then
  echo "ERROR: SOURCE_REPO not set"
  exit 1
fi

has_target=false

# Reason: URL and PAT must come as a pair — one without the other is a config error
if [ -n "${GITLAB_URL:-}" ] && [ -z "${GITLAB_PAT:-}" ]; then
  echo "ERROR: GITLAB_URL set but GITLAB_PAT is empty"
  exit 1
fi
if [ -z "${GITLAB_URL:-}" ] && [ -n "${GITLAB_PAT:-}" ]; then
  echo "ERROR: GITLAB_PAT set but GITLAB_URL is empty"
  exit 1
fi
if [ -n "${GITLAB_URL:-}" ] && [ -n "${GITLAB_PAT:-}" ]; then
  has_target=true
fi

if [ -n "${CODEBERG_URL:-}" ] && [ -z "${CODEBERG_PAT:-}" ]; then
  echo "ERROR: CODEBERG_URL set but CODEBERG_PAT is empty"
  exit 1
fi
if [ -z "${CODEBERG_URL:-}" ] && [ -n "${CODEBERG_PAT:-}" ]; then
  echo "ERROR: CODEBERG_PAT set but CODEBERG_URL is empty"
  exit 1
fi
if [ -n "${CODEBERG_URL:-}" ] && [ -n "${CODEBERG_PAT:-}" ]; then
  has_target=true
fi

if [ "$has_target" = false ]; then
  echo "ERROR: No target configured. Set GITLAB_URL+GITLAB_PAT and/or CODEBERG_URL+CODEBERG_PAT."
  exit 1
fi

echo "Config valid. Source: $SOURCE_REPO"

# --- Mask PATs in CI logs ---
# Reason: ::add-mask:: is a GitHub Actions workflow command; outside GHA it's a no-op
# Redirect to /dev/null when not in GHA to avoid printing PATs
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  [ -n "${GITLAB_PAT:-}" ] && echo "::add-mask::$GITLAB_PAT"
  [ -n "${CODEBERG_PAT:-}" ] && echo "::add-mask::$CODEBERG_PAT"
fi

# --- Clone source as bare repo ---

CLONE_DIR="${TMPDIR:-/tmp}/mirror-repo-$$"
echo "Cloning $SOURCE_REPO (bare)..."
if ! git clone --bare "$SOURCE_REPO" "$CLONE_DIR" 2>&1; then
  echo "ERROR: Failed to clone $SOURCE_REPO"
  exit 2
fi
cd "$CLONE_DIR"

# --- Push to targets ---

push_failed=false

push_mirror() {
  local label="$1" url="$2" pat="$3"
  local push_url="$url"
  # Reason: inject PAT for HTTPS URLs only; local paths don't need auth
  if [[ "$url" == https://* ]]; then
    push_url=$(echo "$url" | sed "s|https://|https://x:${pat}@|")
  fi
  echo "Pushing --mirror to $label ($url)..."
  # Reason: pipe through sed to scrub PAT from git error output (git may embed URL with creds)
  local push_output
  if push_output=$(git push --mirror "$push_url" 2>&1 | sed "s|$pat|***|g"); then
    echo "OK: Pushed to $label"
  else
    echo "$push_output" | sed "s|$pat|***|g"
    echo "ERROR: Failed to push to $label"
    push_failed=true
  fi
}

if [ -n "${GITLAB_URL:-}" ] && [ -n "${GITLAB_PAT:-}" ]; then
  push_mirror "GitLab" "$GITLAB_URL" "$GITLAB_PAT"
fi

if [ -n "${CODEBERG_URL:-}" ] && [ -n "${CODEBERG_PAT:-}" ]; then
  push_mirror "Codeberg" "$CODEBERG_URL" "$CODEBERG_PAT"
fi

# --- Cleanup ---
rm -rf "$CLONE_DIR"

if [ "$push_failed" = true ]; then
  echo "ERROR: One or more push targets failed"
  exit 2
fi

echo "All targets mirrored successfully."
