#!/bin/bash
# Mirror a GitHub repo to GitLab and/or Codeberg.
# Called by action.yaml; expects env vars: SOURCE_REPO, GITLAB_URL, GITLAB_PAT,
# CODEBERG_URL, CODEBERG_PAT.
# Exit codes: 0 = success, 1 = config error, 2 = git error

set -euo pipefail

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
