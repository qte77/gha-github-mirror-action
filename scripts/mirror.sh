#!/bin/bash
# Mirror a repo (GitHub or otherwise) to GitLab, Codeberg, and/or GitHub.
# Called by action.yaml; expects env vars: SOURCE_REPO, SOURCE_PAT, GITLAB_URL,
# GITLAB_PAT, CODEBERG_URL, CODEBERG_PAT, GH_TARGET_URL, GH_TARGET_PAT.
# Exit codes: 0 = success, 1 = config error, 2 = git error

# Reason: wrap entire script in a function so we can filter all output through sed
# to ensure PATs never leak in logs (defense in depth beyond ::add-mask::)
_main() {

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

if [ -n "${GH_TARGET_URL:-}" ] && [ -z "${GH_TARGET_PAT:-}" ]; then
  echo "ERROR: GH_TARGET_URL set but GH_TARGET_PAT is empty"
  exit 1
fi
if [ -z "${GH_TARGET_URL:-}" ] && [ -n "${GH_TARGET_PAT:-}" ]; then
  echo "ERROR: GH_TARGET_PAT set but GH_TARGET_URL is empty"
  exit 1
fi
if [ -n "${GH_TARGET_URL:-}" ] && [ -n "${GH_TARGET_PAT:-}" ]; then
  has_target=true
fi

if [ "$has_target" = false ]; then
  echo "ERROR: No target configured. Set GITLAB_URL+GITLAB_PAT, CODEBERG_URL+CODEBERG_PAT, and/or GH_TARGET_URL+GH_TARGET_PAT."
  exit 1
fi

# Reason: reject PAT charsets outside the safe range before they ever reach a URL
# or a git argv — turns "the substitution/URL is safe because real PAT charsets
# happen not to collide with the delimiter" into safe-by-construction. A PAT
# containing @, :, /, %, #, ? would also break URL userinfo parsing regardless of
# the scrub mechanism. `.` is allowed: GitHub's installation tokens (including
# GITHUB_TOKEN / github.token) are rolling out a ghs_APPID_JWT format — a JWT,
# which uses `.` as a segment separator (github.blog changelog, 2026-04-24).
# GitHub explicitly recommends against hardcoded token-format validation, but
# this guard exists for our own URL/argv safety, not to mirror GitHub's format —
# `.` is safe in both contexts, so the charset widens rather than being dropped.
for _pat_var in SOURCE_PAT GITLAB_PAT CODEBERG_PAT GH_TARGET_PAT; do
  _pat_val="${!_pat_var:-}"
  if [ -n "$_pat_val" ] && [[ ! "$_pat_val" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "ERROR: $_pat_var contains invalid characters (must match ^[A-Za-z0-9_.-]+\$)"
    exit 1
  fi
done

# Reason: refuse to mirror into the repo running this action — push --mirror would
# clobber the workflow currently executing. Scoped to https:// form only: every
# target URL input is documented as an HTTPS URL, so ssh://host:path self-targets
# are out of the documented contract rather than silently unguarded against a
# supported input. Only meaningful inside GHA, where GITHUB_REPOSITORY identifies
# the running repo.
if [ -n "${GITHUB_ACTIONS:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ]; then
  _hub_repo="${GITHUB_SERVER_URL:-}/${GITHUB_REPOSITORY}"
  _hub_repo="${_hub_repo%/}"
  _hub_repo="${_hub_repo%.git}"
  _hub_repo="${_hub_repo,,}"
  for _target_url in "${GITLAB_URL:-}" "${CODEBERG_URL:-}" "${GH_TARGET_URL:-}"; do
    if [[ "$_target_url" == https://* ]]; then
      _norm_url="${_target_url%/}"
      _norm_url="${_norm_url%.git}"
      _norm_url="${_norm_url,,}"
      if [ "$_norm_url" = "$_hub_repo" ]; then
        echo "ERROR: Refusing to mirror into the repo running this action ($_target_url)"
        exit 1
      fi
    fi
  done
fi

echo "Config valid. Source: $SOURCE_REPO"

# --- Clone source as bare repo ---

CLONE_DIR="${TMPDIR:-/tmp}/mirror-repo-$$"
# Reason: clean up the clone dir on every exit path (success, config/git error, or
# cancellation) — not just an explicit rm -rf on the historical success path.
trap 'rm -rf "$CLONE_DIR"' EXIT

clone_url="$SOURCE_REPO"
# Reason: inject the source PAT for HTTPS URLs only, by string substitution rather
# than sed, so the PAT never appears in a separate process's argv (visible via
# ps/proc on a shared runner). Never overwrite SOURCE_REPO itself — log lines
# below stay uncredentialed.
if [[ "$SOURCE_REPO" == https://* ]] && [ -n "${SOURCE_PAT:-}" ]; then
  clone_url="https://x:${SOURCE_PAT}@${SOURCE_REPO#https://}"
fi

echo "Cloning $SOURCE_REPO (bare)..."
# Reason: credential.helper= stops a runner-level helper from persisting the
# URL-embedded credential; output is captured (not streamed) so it can be scrubbed
# before ever reaching a terminal or log.
clone_output=$(git -c credential.helper= clone --bare "$clone_url" "$CLONE_DIR" 2>&1)
clone_status=$?
if [ -n "${SOURCE_PAT:-}" ]; then
  clone_output="${clone_output//"$SOURCE_PAT"/***}"
fi
echo "$clone_output"
if [ "$clone_status" -ne 0 ]; then
  echo "ERROR: Failed to clone $SOURCE_REPO"
  exit 2
fi

# Reason: rewrite origin back to the uncredentialed SOURCE_REPO so the injected
# credential doesn't sit in $CLONE_DIR/config for the rest of the run.
git -C "$CLONE_DIR" remote set-url origin "$SOURCE_REPO"

# --- Push to targets ---

push_failed=false

push_mirror() {
  local label="$1" url="$2" pat="$3"
  local push_url="$url"
  # Reason: inject PAT for HTTPS URLs only, by string substitution rather than
  # sed, so the PAT never appears in a separate process's argv.
  if [[ "$url" == https://* ]]; then
    push_url="https://x:${pat}@${url#https://}"
  fi
  echo "Pushing --mirror to $label ($url)..."
  local push_output
  push_output=$(git -C "$CLONE_DIR" -c credential.helper= push --mirror "$push_url" 2>&1)
  local push_status=$?
  if [ "$push_status" -eq 0 ]; then
    echo "OK: Pushed to $label"
  else
    echo "${push_output//"$pat"/***}"
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

if [ -n "${GH_TARGET_URL:-}" ] && [ -n "${GH_TARGET_PAT:-}" ]; then
  push_mirror "GitHub" "$GH_TARGET_URL" "$GH_TARGET_PAT"
fi

# --- Cleanup ---
# Reason: handled by the `trap ... EXIT` set above, which covers every exit path.

if [ "$push_failed" = true ]; then
  echo "ERROR: One or more push targets failed"
  exit 2
fi

echo "All targets mirrored successfully."

} # end _main

# --- Mask PATs in CI logs ---
# Reason: ::add-mask:: is a GitHub Actions workflow command that must be emitted at
# top level, with the real value, before _main's output is piped through sed below
# — a workflow command emitted from inside that piped subshell would already be
# scrubbed to `::add-mask::***` by the time the runner sees it, so add-mask would
# never actually mask anything. Outside GHA the string is a harmless no-op, but
# it's still gated on GITHUB_ACTIONS to avoid printing raw PATs needlessly.
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  [ -n "${SOURCE_PAT:-}" ] && echo "::add-mask::$SOURCE_PAT"
  [ -n "${GITLAB_PAT:-}" ] && echo "::add-mask::$GITLAB_PAT"
  [ -n "${CODEBERG_PAT:-}" ] && echo "::add-mask::$CODEBERG_PAT"
  [ -n "${GH_TARGET_PAT:-}" ] && echo "::add-mask::$GH_TARGET_PAT"
fi

# Reason: run _main and scrub all PATs from combined stdout+stderr as a redundant
# last-resort net; the charset guard, argv-safe bash substitution, remote set-url
# disk scrub, and credential.helper= above fix the primary path, so this outer sed
# is now belt-and-suspenders rather than the only line of defense.
# Build sed expression to replace all configured PATs with ***
_sed_expr=""
[ -n "${SOURCE_PAT:-}" ] && _sed_expr="${_sed_expr}s|${SOURCE_PAT}|***|g;"
[ -n "${GITLAB_PAT:-}" ] && _sed_expr="${_sed_expr}s|${GITLAB_PAT}|***|g;"
[ -n "${CODEBERG_PAT:-}" ] && _sed_expr="${_sed_expr}s|${CODEBERG_PAT}|***|g;"
[ -n "${GH_TARGET_PAT:-}" ] && _sed_expr="${_sed_expr}s|${GH_TARGET_PAT}|***|g;"

if [ -n "$_sed_expr" ]; then
  _main 2>&1 | sed "$_sed_expr"
  exit "${PIPESTATUS[0]}"
else
  _main
fi
