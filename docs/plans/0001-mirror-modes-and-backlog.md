# Arc 0001 — Mirror modes (source auth · GitHub target · router) + backlog sweep

Drafted in plan mode 2026-09-09; HEAD `85aa1a6` at draft time.

## Status — read this first (handoff)

**Shipped:** P0 — PR #40 (squash-merged): fixed global git identity mutation (`setup()` used
`git config --global user.name/email`, now `GIT_AUTHOR_*`/`GIT_COMMITTER_*` env vars scoped to the
test process), fixed gpg-signing rejection on machines with `commit.gpgsign=true`, added `teardown()`
to `test_mirror.bats` so reruns don't collide with leftover fixtures. **Incident note:** running
`bats` for P0's own verification triggered the pre-existing bug and briefly clobbered the operator's
real global git identity to `test <test@test>`; caught via user alert, root-caused, fixed, and the
operator restored their identity (`qte77 <93844790+qte77@users.noreply.github.com>`) before this fix
was committed with the correct authorship. **Overall:** ~5 %. **Tracking issue:** #41.

**Auth gotcha found during P0 (added to every future `git push`/`gh` call):** unset BOTH `GH_TOKEN`
(invalid) and `GITHUB_TOKEN` (a sandbox-injected token that lacks write access to this repo) — only
then does `gh`/`git` fall back to the keyring login with proper `repo` scope. `gh pr checks --watch`
output was also observed to be unreliable/inconsistent (an RTK-hook-filtered summary) — use
`rtk proxy gh pr checks <n> --repo ...` for the raw, trustworthy per-check list before merging.

**You are the next session. Do this, in order:**

1. **P0 — prove the shell works before anything else.** DONE (see Shipped). If a fresh session hits
   permission denials again, re-diagnose from the actual denial text before fanning out.
2. Row **A0** on the main thread: create this file (already done — you're reading it), file the
   tracking issue, PR `docs: add arc 0001 plan`, squash-merge.
3. Row **A1**: squash-merge dependabot PRs #38 and #39 (authorized by plan approval) — BEFORE A2,
   otherwise the grouped config closes them and re-opens one grouped PR (churn).
4. **Check gates, then fan out every UNBLOCKED A-row in ONE message** — A2, A3, A4, A5, A6 are
   unblocked; A7 only if canon is final, A8 only if qte77/.github#33 is merged (one `gh` check each,
   30 s). Each `Agent(subagent_type: "general-purpose", isolation: "worktree")`, one branch per row
   (names in the table); give each subagent its row, the Source map, the Design decisions, and (A4)
   the RED/GREEN tables verbatim. Each subagent: RED bats test first (module rows only) → GREEN →
   run the gate (Commands) → `git push -u` → `gh pr create` (PR template) → report PR number. Do
   NOT merge from inside a worktree; the main thread merges after CI is green, deleting remote +
   local branches.
5. Merge order (README and `scripts/mirror.sh` are serialized resources): **A1 → A2 → A3 → A4 →
   A5 → A6**; A7/A8 merge whenever their gate clears, and any README-touching PR still open at that
   moment rebases. Every PR rebases onto `main` right before merge. No row waits on another row's
   *code* — only on merge order (A4 rebases onto A3 for shellcheck; A5's dispatch check needs A4's
   inputs on its own branch, so A5 rebases onto A4 before that check).
6. Strike each row in the SAME PR that ships it (edit this file), append the PR number, keep this
   Status block current.
7. When A-rows are done: post the progress report (shipped · next · % · blocked+pre-staged) and stop
   at the **Owner checkpoint** (Phase B). Do not start C-rows until B1–B4 are confirmed.

**Loop per row:** branch → RED → GREEN → gate → push → PR → CI green → squash-merge → strike row →
delete branches. **Decide-by-default:** every open choice below has a default; proceed with it.

**Commands (exact CI gate, run before every push):**

```bash
TMPDIR=/tmp bats tests/unit/                       # test.yaml gate
shellcheck scripts/*.sh .github/scripts/*.sh       # once A3 lands (same flags as the CI step)
actionlint                                         # once A3 lands
# unset BOTH tokens — GH_TOKEN is invalid, GITHUB_TOKEN lacks write access to this repo;
# only then does gh/git fall back to the keyring login with proper `repo` scope
unset GH_TOKEN GITHUB_TOKEN; gh pr checks <n> --repo qte77/gha-github-mirror-action
# `gh pr checks --watch`'s summary was observed inconsistent (RTK-hook-filtered) — get the
# raw per-check list before deciding to merge:
unset GH_TOKEN GITHUB_TOKEN; rtk proxy gh pr checks <n> --repo qte77/gha-github-mirror-action
```

**Watch-outs:** hub pins `@v0` (nothing hub-side is live until B4 moves the tag; an unknown `with:`
input on the old tag is reported to warn, not fail — treat as runner behaviour, not a docs citation,
per F-list below) · secret names cannot start with `GITHUB_` (VERIFIED) → but a `GITHUB_`-prefixed
key IS accepted as composite-step `env:` (file-verified: `action.yaml:34`, `bump-and-release.yaml:85`
already do it) — the naming rule is about *secrets*, not step-env keys · `git push --mirror` into a
*non-empty* GitHub target force-updates/deletes refs and fails on protected branches/rulesets (exit
2 — rejection behaviour itself is runner behaviour, not a fetched doc quote) · the plan link in
issues #7–#11 (`~/.claude/plans/github-mirror-backup-research.md`) is dangling here — this repo plan
is canonical · `pyproject.toml` bump-my-version CHANGELOG `search` is `## [Unreleased]\n\n---` but
the current CHANGELOG has `### Added` content between them → the bump may fail; A6 pre-stages the
fix with a `--dry-run` so B4 is a pure "go" · the fake-`git` shim is opt-in per test, never in
`setup()` (setup seeds repos with real `git`) · CI runs bats with `GITHUB_ACTIONS=true`, so
`setup()` must `unset GITHUB_ACTIONS GITHUB_SERVER_URL GITHUB_REPOSITORY` once add-mask is fixed ·
never set `GIT_TRACE_REDACT=0` (git would print auth headers no scrub can match) · **`repos.yaml` is
a trust boundary**: anyone who can merge to `main` can point any configured PAT at any URL listed as
`source` — document this rather than trying to code around it. · **Before running any unfamiliar
test suite's `setup()`/fixture code for the first time, read it for side effects on shared/global
state (git config, env, files outside the repo) — do not execute blind** (see P0 incident above).

## Context (why)

`qte77/gha-github-mirror-action` mirrors **out of** GitHub only: the repo running the action (or any
*public* `source_repo`) is bare-cloned **without credentials** and `git push --mirror`ed to GitLab
and/or Codeberg with a PAT injected into the HTTPS URL. Two more shapes were requested:

1. **Invert / pull** — mirror *from* a repo on another host/account *into* a GitHub repo on the
   account running the action.
2. **Router** — the account running the action is neither source nor target (e.g. GitLab acct A →
   Codeberg acct B); it only supplies compute.

Both reduce to two gaps: (a) the clone step cannot authenticate (`scripts/mirror.sh:67`); (b) GitHub
is not a push *target*. `push_mirror` is already host-agnostic, so an authenticated source plus a
third `github_url`/`github_pat` pair gives all three modes through one code path. `github.token` is
NOT the GitHub-target credential: it only has rights on the repo running the workflow, and
`push --mirror` into that repo would clobber the workflow — hence a PAT input like the other hosts,
plus a self-clobber guard.

Design review surfaced two shipped bugs the arc fixes on the way: `::add-mask::` never reaches the
runner intact (emitted inside the scrubbed pipeline), and the hub passes PATs unconditionally while
the script rejects PAT-without-URL.

The arc also absorbs this session's backlog triage (dependabot grouping, two open bot PRs, issues #7–#11
/ #33 / #36) so the repo has ONE plan and ONE remaining-work table.

## Source map (verified 2026-09-09 — three Explore agents + direct reads; line refs at HEAD `85aa1a6`)

| Path | What matters |
|---|---|
| `action.yaml` (44 l) | Inputs `source_repo`, `gitlab_url/pat`, `codeberg_url/pat` (l.8-28). Step env l.33-41: `GITHUB_TOKEN: ''`, `GH_TOKEN: ${{ github.token }}` (**dead** — never read; keep, `test_infra_files.bats:22-24` asserts it), `SOURCE_REPO` default `${{ github.server_url }}/${{ github.repository }}.git`, `GITLAB_*`, `CODEBERG_*`; `run: ${{ github.action_path }}/scripts/mirror.sh`. |
| `scripts/mirror.sh` (128 l) | `_main()` l.9; `set -uo pipefail` (no `-e`) l.12; pair validation l.21-51 (URL⇔PAT, ≥1 target; message "No target configured" l.49); `::add-mask::` l.58-61 **inside `_main` → scrubbed to `::add-mask::***` by l.123 (BUG)**; **clone without auth l.67**, exit 2 on failure l.68-70 **before cleanup (clone dir + URL-embedded creds left on disk)**; `push_mirror label url pat` l.77-94 — https-only inject `sed "s\|https://\|https://x:${pat}@\|"` l.81-83, output scrub l.87/90; hard-wired GitLab/Codeberg calls l.96-102; `rm -rf` l.105; exit 1=config 2=git; trailing whole-output scrub l.118-127 (`PIPESTATUS[0]`). |
| `scripts/clone-local.sh` (75 l) | Local bare-mirror script; shares `repos.yaml` shape. Second shellcheck target. |
| `tests/unit/test_mirror.bats` (14 tests) | `MIRROR_SH="$BATS_TEST_DIRNAME/../../scripts/mirror.sh"` l.5; `setup()` sets `TMPDIR`, git identity via `GIT_AUTHOR_*`/`GIT_COMMITTER_*` env vars (fixed by PR #40 — was `git config --global`), disables gpgsign for the test process, unsets config env; `teardown()` removes fixture dirs (added by PR #40). Pattern: seed local bare src (`git init --bare` + clone + empty commit + push), export env, `run "$MIRROR_SH"`, assert `$status`/`$output` with `[ ]`/`[[ ]]`+`\|\|`. Failure = nonexistent local path. Existing tests match substrings `*PAT*`/`*URL*`/`No target configured`/`gitlab`/`GitLab`. **https injection branch: zero coverage.** |
| `tests/unit/test_clone_local.bats` | Same PR #40 fix applied to its `setup()`. Stub precedent: writes a PATH-prepended `$BATS_TEST_DIRNAME/_stubs/yq`, `teardown()` removes it; helper `_make_config`. |
| `tests/unit/test_infra_files.bats` (17 tests) | grep meta-tests; asserts `GITHUB_TOKEN: ''` in action.yaml; asserts `source_repo` input. None break with the planned edits. |
| `.github/workflows/test.yaml` (28 l) | `permissions: contents: read`; clone bats-core `--depth 1` → `sudo install.sh /usr/local` → `bats tests/unit/` with `TMPDIR: /tmp`. **A3 adds shellcheck/actionlint here.** |
| `.github/workflows/integration.yaml` (55 l) | `permissions: contents: read`; step `setup` seeds `/tmp/self-test-source` + `/tmp/self-test-target`; `uses: ./` with `source_repo`, `gitlab_url`=local path, `gitlab_pat: dummy-pat`; verify `rev-list --count --all ≥ 1`. **The test for YAML wiring — extend, never unit-test YAML.** |
| `.github/workflows/mirror-all.yaml` (35 l) | Hub: cron `0 2 * * *` + `workflow_dispatch`; job `load` → `yq -o=json config/repos.yaml` → `outputs.matrix`; job `mirror` `if: != '[]'`, `fail-fast: false`, `uses: qte77/gha-github-mirror-action@v0` with `source_repo: ${{ matrix.repo.source }}`, `gitlab_url/pat`, `codeberg_url/pat` — **PATs passed unconditionally (BUG)**. **No `permissions:` block.** |
| `config/repos.yaml` (8 l) | Header comment = schema (`source` GitHub, `gitlab`, `codeberg` optional) + example; body `[]`. |
| `.github/workflows/codeql.yaml` | CodeQL `languages: actions`, cron Mon 06:00. |
| `.github/workflows/lint-md-links.yml` | Reusable `qte77/.github/.github/workflows/lint-md-links.yml@5dfff1f…` — markdownlint-cli2 + lychee (`fail: true`), configs fetched from `qte77/.github` main. Docs PRs must pass it. |
| `.github/workflows/bump-and-release.yaml` | `workflow_dispatch(bump_type)` → `callowayproject/bump-my-version` → signed commit on `bump-<run>-main` → tag `vX.Y.Z` → PR `[skip ci bump]` → release → force-move floating `vX`. **Only path by which hub `@v0` sees new inputs.** |
| `.github/dependabot.yml` | `github-actions`, `/`, weekly, no `groups:` (7 PRs all-time; `bump-my-version` alone caused 3 cycles in 7 weeks). |
| `README.md` (99 l) | Usage per-repo (`@v1` — no such tag; use `@v0`) / hub / local; "What it does" (**"Masks all PATs in CI logs" is false today**); Inputs table; Development `bats tests/unit/`; **badge says MIT, §License + LICENSE say Apache-2.0**; badge version `0.1.0`. |
| `CHANGELOG.md` (26 l) | Keep-a-Changelog; only `## [Unreleased]` → `### Added`, then `---`. Test counts stale (says 16+13; actual 17+14). |
| `pyproject.toml` | `[project] version = "0.1.0"`, `[tool.bumpversion]` files: pyproject, README badge, CHANGELOG (search `## [Unreleased]\n\n---`). |
| `.claude/settings.json` | Plugins `commit-helper`, `tdd-core`, `gha-dev`, `docs-governance`; no hooks/rules. `settings.local.json` (ignored) allows only `uv …`. |
| `.gitmessage`, `.github/pull_request_template.md` | Conventional Commits (`type(scope): …`); PR template = Summary + Test plan (`bats tests/unit/` local, CI). |
| Absent | `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `AGENT_LEARNINGS.md`, Makefile, shellcheck/actionlint/yamllint, `changelog.d/`, `tests/integration/`. |

**External refs:** PRs #38 (`github/codeql-action` 4→4.37.4), #39 (`callowayproject/bump-my-version`
1.4.1→1.5.1) — dependabot, 8/8 checks green, `CLEAN`. Issues #7 GitLab acct, #8 Codeberg acct, #9
secrets, #10 single-repo test, #11 full rollout (`setup`/`rollout` labels; sequential chain); #33
README canon (refs qte77/qte77#124, #126; comment has itemized checklist); #36 reusable release
workflows (blocked on qte77/.github#33). Labels: `enhancement`, `documentation`, `setup`,
`testing`, `rollout`, `github_actions`, `dependencies`.

**Verified vendor facts (docs.github.com, fetched 2026-09-09):** secret names "Must not start with
the `GITHUB_` prefix", alphanumeric/`_` only, no leading digit, case-insensitive. Dereferencing a
nonexistent context property "will evaluate to an empty string". Falsy values are exactly
`false, 0, -0, "", '', null`. Dynamic `secrets[<expr>]` indexing is reported unsupported
(community #25171 accepted answer) — not relied on.

**Explicitly NOT vendor-documented — cite as runner-observed behaviour in any issue/PR body, never
as "per the docs" (per the project's claim-verification rule):** (1) that `&&`/`||` return an
operand value rather than a boolean, i.e. the `cond && a || b` ternary idiom — the word "ternary"
does not appear on the expressions page; `&&`/`||` are documented only as "And"/"Or" — **verify at
A5 via actionlint + the branch-dispatch syntax check**; (2) a `GITHUB_`-prefixed key being accepted
in a composite step's `env:` (file-verified only); (3) an unrecognized `with:` input producing a
warning rather than a failure; (4) a PAT working as an HTTPS basic-auth password under an arbitrary
username (`x`) for GitHub/GitLab/Codeberg, and whether `x-access-token` specifically is required for
GitHub installation tokens — **verify at A4 via the `integration.yaml` `github.token` step**; (5)
exact PAT charsets per host; (6) `git --mirror` force/prune semantics, `GIT_TRACE_REDACT` default,
credential-helper "approve" behaviour on URL-sourced creds; (7) GitHub owner/repo case-insensitivity,
protected-branch/ruleset rejection of a force-push; (8) whether `shellcheck`/`yq` are preinstalled on
`ubuntu-latest`, and any `actionlint`/`zizmor` pinned version — **A3 fetches current facts, doesn't
guess.**

## Approach

**Phase A — agent-only (parallel worktrees).** A0 (plan + issue) and A1 (merge bots) on the main
thread; A2–A6 fanned out in one message, one worktree each (A7/A8 when their gates clear); merge in
the stated order. Every feature row ships dormant-safe: new inputs are optional, defaults preserve
today's behaviour, hub wiring is inert until secrets + release exist (build-behind-gate).

**Phase B — one owner sitting.** Accounts/PATs (#7, #8), secrets (#9 + `GH_TARGET_PAT`), release
"go". All pre-staged by Phase A (exact secret names, exact `gh` commands, green bump dry-run).

**Phase C — activation.** Hub single-repo test (#10), full rollout (#11), invert e2e against a real
external source, close issues.

### Design decisions (final — override only with evidence, and record it here)

- **Names.** Inputs `source_pat`, `github_url`, `github_pat` → env `SOURCE_PAT`, `GH_TARGET_URL`,
  `GH_TARGET_PAT`. Hub secret `GH_TARGET_PAT` (same word everywhere; `GITHUB_*` is reserved, bare
  `GH_*` is the gh-CLI namespace). Existing `GITHUB_TOKEN: ''`/`GH_TOKEN` env untouched.
- **GitHub target = third `push_mirror` call**, label `GitHub`, same pairing validation. No loop
  refactor (AHA).
- **Source auth.** Build `clone_url` from `SOURCE_REPO`; inject `x:${SOURCE_PAT}@` only when the
  URL is `https://*` AND `SOURCE_PAT` non-empty (same `sed` as l.82); never overwrite `SOURCE_REPO`
  (log lines stay clean). Clone stderr is covered by the trailing scrub (extend `_sed_expr`) — no
  second inline `sed`. Username stays `x` for all hosts (today's convention); if the `github.token`
  integration step (below) returns 401, switch the *clone* username to `x-access-token` (GitHub's
  documented form for installation tokens; any username works for PATs) — one string, record here.
- **Self-clobber guard** in the validation block, before clone, only when `GITHUB_ACTIONS` and
  `GITHUB_REPOSITORY` are set: for each of the three target URLs, strip `.git`/trailing `/`,
  lowercase (`${u,,}`, bash ≥4), and compare to `${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}`
  lowercased → `echo "ERROR: Refusing to mirror into the repo running this action ($url)"; exit 1`.
  A different repo in the same account passes. **Scoped to `https://` form only** — every URL input
  is documented as "Target … HTTPS URL", so `ssh://`/`git@host:path` self-targets are out of the
  documented contract, not silently unguarded against a supported input (YAGNI; note it in README as
  a known limit rather than normalizing scp-syntax for a case nothing else in the action supports).
  **Wiring proof, no external accounts needed:** `integration.yaml` gets a 4th step — `github_url`
  set to the *actual running repo's own URL* (`${{ github.server_url }}/${{ github.repository }}.git`),
  `continue-on-error: true`, then a check step asserting `steps.<id>.outcome == 'failure'`. This
  moves the negative test out of C3 (which needed a real external source) into Phase A.
- **Fix add-mask (shipped bug).** Emit `::add-mask::<PAT>` for every configured PAT (incl. the two
  new ones) at top level, *before* the `_main | sed` pipeline, when `GITHUB_ACTIONS` is set. Only
  there does the runner see the real value.
- **Credential hardening (from security review, file/reasoning-verified, all within A4's diff):**
  (a) validate every configured PAT against `^[A-Za-z0-9_-]+$` before use, `exit 1` on a bad one —
  turns "the sed/URL is safe because real PAT charsets happen not to collide" into safe-by-construction;
  (b) build the injected URL by string substitution, not `sed`, and scrub captured command output
  with bash `${var//"$pat"/***}` (quoting `"$pat"` forces a literal, non-glob match) instead of piping
  through a separate `sed` process — removes the PAT from that process's argv (visible via `ps`/`/proc`
  on a shared runner); (c) after a successful clone, `git -C "$CLONE_DIR" remote set-url origin
  "$SOURCE_REPO"` so the credentialed URL doesn't sit in `$CLONE_DIR/config` for the run's duration;
  (d) `trap 'rm -rf "$CLONE_DIR"' EXIT` inside `_main` (covers the clone-failure path and cancellation,
  not just the success path's explicit `rm -rf`); (e) run clone/push with `git -c
  credential.helper=` so no runner-level helper can persist the URL-embedded credential. The outer
  `_main | sed "$_sed_expr"` tail stays as a redundant last-resort net (file's own words: "defense in
  depth beyond `::add-mask::`") — (a)-(e) fix the primary path, the outer sed is now
  belt-and-suspenders rather than the only line of defense.
- **Credential transport stays URL-embedded** (`https://x:<PAT>@…`) as today; `http.extraheader`
  was considered and rejected for this arc (would rewrite every RED test; the (a)-(e) hardening above
  closes the leaks that motivated considering it). Document: never set `GIT_TRACE_REDACT=0`; a PAT
  containing `@`, `:`, `/`, `%`, `#`, `?` would also break URL userinfo parsing regardless of the
  scrub mechanism — the charset guard (a) rejects these before they reach git.
- **Trust-boundary note, not a code fix:** with static per-host secrets (below), anyone who can merge
  a `repos.yaml` change to `main` can direct any configured PAT at any URL listed as `source` —
  document this in README/CONTRIBUTING rather than trying to sandbox it (out of scope for this arc).
- **Hub gating (shipped bug + new).** Every PAT passed only when its URL is present:
  `gitlab_pat: ${{ matrix.repo.gitlab && secrets.GITLAB_PAT || '' }}` (same for codeberg, github).
  Note the idiom's one sharp edge (reasoning-verified from the documented falsy list): if the
  left-hand condition is true but the right-hand secret is itself empty/unset, the whole expression
  still falls through to the same `''` fallback — it cannot distinguish "no target" from "target set,
  secret missing". That's fine here because the fallback is `''` either way and `mirror.sh`'s own
  strict URL⇔PAT pairing check is what surfaces a missing secret (exit 1) — never give this idiom a
  non-empty fallback, or that safety net disappears.
  Source PAT derived from the source host with the SAME three secrets, reused for both directions:
  `source_pat: ${{ contains(matrix.repo.source, 'gitlab.com') && secrets.GITLAB_PAT || contains(matrix.repo.source, 'codeberg.org') && secrets.CODEBERG_PAT || contains(matrix.repo.source, 'github.com') && secrets.GH_TARGET_PAT || '' }}`
  → router mode reuses the three PATs. **Accepted tradeoff:** this means a PAT used as a target
  credential also authenticates reads if that same host is ever a source (B1/B2 already say "add
  read scope if it'll be a source too") — simpler than minting six separate least-privilege secrets
  (3 write-only target + 3 read-only source), at the cost of one PAT per host doing double duty.
  Deferred hardening, not done now: split into per-direction secrets (`SOURCE_PAT_GITLAB` etc.) if
  least-privilege separation is ever required. **Hub limitation from this reuse:** it assumes source
  and target on the same host share one account — a same-host cross-account router (e.g. GitLab
  account A → GitLab account B) can't work through the hub with a single `GITLAB_PAT`, since a
  write-scoped target credential presented back to the source host would be for the wrong account.
  The per-repo marketplace action (not the hub) already covers that case via its own `source_pat`
  input, so nothing is blocked — just don't expect the hub's `repos.yaml` schema to support it.
  `repos.yaml` gains only an optional `github` field.
  `permissions: contents: read` added. Fallback if the ternary idiom fails the A5 syntax check: one
  `SOURCE_PAT` secret for all entries.
- **Tests.** `mirror.sh` is a module → RED bats tests (table below). YAML wiring → `integration.yaml`
  only. No new grep meta-tests. https path tested with an **opt-in per-test fake `git`** (helper
  `_use_git_shim`, dir `$TMPDIR/git-shim-$BATS_TEST_NUMBER/`, never in `setup()`, never in the shared
  `_stubs/`): logs argv to `$GIT_SHIM_LOG`; on `clone` does `mkdir -p "${@: -1}"`; when
  `GIT_SHIM_FAIL` equals the subcommand, prints `fatal: simulated failure: $*` to stderr and exits 128.
  `setup()` additionally unsets `SOURCE_PAT GH_TARGET_URL GH_TARGET_PAT GIT_SHIM_FAIL GITHUB_ACTIONS
  GITHUB_SERVER_URL GITHUB_REPOSITORY`.
- **No implicit `source_pat` default** (e.g. `github.token` when `source_repo` is empty) — explicit
  input only (YAGNI). README may state "`source_pat: ${{ github.token }}` works for a private
  self-source" ONLY after the integration step proving it is green.

### RED tests (row A4 — `tests/unit/test_mirror.bats`; each fails today for the stated reason)

| # | Test | Setup | Assertion |
|---|---|---|---|
| 1 | fails when github URL set without PAT | `SOURCE_REPO=$TMPDIR/nonexistent-$N`; valid local `GITLAB_URL`+`GITLAB_PAT=fake`; `GH_TARGET_URL=https://github.com/t/o.git`, `GH_TARGET_PAT=""` | `status==1`; output contains `GH_TARGET_PAT` (today: 2, falls through to clone) |
| 2 | fails when github PAT set without URL | as 1 with `GH_TARGET_PAT=fake`, `GH_TARGET_URL=""` | `status==1`; output contains `GH_TARGET_URL` (today: 2) |
| 3 | pushes --mirror to github target | real git: local bare src (+1 commit) and bare target; `GH_TARGET_URL=$target GH_TARGET_PAT=fake` | `status==0`; output contains `GitHub`; target `rev-list --count --all ≥ 1` (today: 1 "No target configured") |
| 4 | injects source PAT into https clone URL, then scrubs the credential from disk | `_use_git_shim`; `SOURCE_REPO=https://gitlab.com/a/r.git SOURCE_PAT=glpat-src-secret`; valid local gitlab pair | `status==0`; shim log contains `clone --bare https://x:glpat-src-secret@gitlab.com/a/r.git` followed by a `remote set-url origin https://gitlab.com/a/r.git` line (no credential in it); output does not contain the PAT (today: no `x:` prefix, no `remote set-url` call at all) |
| 5 | scrubs source PAT from clone failure output | as 4 + `GIT_SHIM_FAIL=clone` | `status==2`; output contains `***` and `Failed to clone https://gitlab.com/a/r.git`, never `glpat-src-secret` (today: no `***` at all). The argv-safe-scrub property (no separate `sed` process carrying the PAT) is a code-review check on the GREEN diff, not independently bats-observable — confirm by reading the diff, not by adding a process-inspection assertion. |
| 6 | injects github PAT into https push URL and scrubs failure the same argv-safe way | shim, `GIT_SHIM_FAIL=push`; plain local `SOURCE_REPO`; `GH_TARGET_URL=https://github.com/o/r.git GH_TARGET_PAT=ghp-supersecret` | `status==2`; log contains `push --mirror https://x:ghp-supersecret@github.com/o/r.git`; output contains `***` and `Failed to push to GitHub`, never the PAT — **first coverage of the shared https branch** |
| 7 | refuses to mirror into the repo running the action | `GITHUB_ACTIONS=true GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=Me/Hub`; `SOURCE_REPO=$TMPDIR/nonexistent-$N` (guard must fire before clone); valid local gitlab pair; `GH_TARGET_URL=https://github.com/me/hub.git GH_TARGET_PAT=fake` (mixed case + `.git`, proves normalisation) | `status==1`; output contains `Refusing` (today: 2) |
| 8 | emits add-mask with the real PAT when running in GHA | `GITHUB_ACTIONS=true` (no `GITHUB_REPOSITORY`); real local src + local gitlab target; `GITLAB_PAT=glpat-mask-me` | `status==0`; output contains the line `::add-mask::glpat-mask-me`; the PAT appears in **no other** line (today: `::add-mask::***`) |
| 9 | leaves no clone dir behind when clone fails | `SOURCE_REPO=$TMPDIR/nonexistent-$N`; valid local gitlab pair; `TMPDIR` set to a fresh dir | `status==2`; `ls "$TMPDIR"` shows no `mirror-repo-*` (regression guard for the new `trap`; drop if already green before GREEN) |
| 10 | rejects a PAT containing characters outside `[A-Za-z0-9_-]` | valid local `SOURCE_REPO`; `GITLAB_URL=https://gitlab.com/a/r.git GITLAB_PAT='bad;pat'` | `status==1`; output names the offending var and says the PAT has invalid characters (today: PAT accepted as-is, status 0 or 2 depending on what git does with it) |

Existing test "PAT not visible in error output" stays valid because `setup()` unsets `GITHUB_ACTIONS`
(no add-mask line without it).

### GREEN changes (row A4)

- `scripts/mirror.sh`: header (+3 env vars) · PAT charset validation (`^[A-Za-z0-9_-]+$`, exit 1) for
  every configured PAT, in the validation block · third pairing block · message lists the third pair
  (keep "No target configured") · self-clobber guard, https-form only · **remove** the mask block
  from `_main` · `trap 'rm -rf "$CLONE_DIR"' EXIT` · `clone_url` built by string substitution (no
  `sed`) + `git -c credential.helper= clone "$clone_url"`, then `git -C "$CLONE_DIR" remote set-url
  origin "$SOURCE_REPO"` to scrub the credential out of the stored git config · clone/push output
  captured into a variable and scrubbed with bash `${var//"$pat"/***}` (quoted pattern = literal
  match, no glob surprises) instead of piping through `sed` · `push_mirror` uses `git -c
  credential.helper= push` · third `push_mirror "GitHub"` call · top level: add-mask loop (when
  `GITHUB_ACTIONS`) BEFORE building `_sed_expr`, then extend `_sed_expr` with `SOURCE_PAT`,
  `GH_TARGET_PAT` (this outer sed stays as the redundant last-resort net; the bash substitution above
  is now the primary scrub). `# Reason:` comment on the guard, the add-mask placement, the charset
  guard, and the `remote set-url` scrub.
- `action.yaml`: description mentions GitHub target; inputs `source_pat`, `github_url`, `github_pat`
  (optional, `default: ''`; `github_url` description: "must not be the repo running the action");
  env `SOURCE_PAT`, `GH_TARGET_URL`, `GH_TARGET_PAT`.
- `tests/unit/test_mirror.bats`: `_use_git_shim` helper; `setup()` unset list; tests 1-10.
- `.github/workflows/integration.yaml`: setup seeds a second bare target `target_gh`; step 2
  `uses: ./` with `source_repo`, `source_pat: dummy-src-pat` (local source → proves no injection on
  non-https), `gitlab_url`, `gitlab_pat: dummy-pat`, `github_url: target_gh`, `github_pat: dummy-pat`;
  verify both targets ≥1 commit; step 3 **`github.token` self-source proof**: no `source_repo`,
  `source_pat: ${{ github.token }}`, fresh local bare `gitlab_url`, `gitlab_pat: dummy-pat`, verify
  ≥1 commit (GitHub 401s bad supplied creds even on public repos, so green is conclusive; on 401 see
  the username decision above). Step 2 also exercises the guard under real `GITHUB_ACTIONS` without
  tripping it. Step 4 **negative self-clobber proof** (no external account needed): `github_url:
  ${{ github.server_url }}/${{ github.repository }}.git`, `github_pat: dummy-pat`,
  `continue-on-error: true`, then a check step asserting `steps.<id>.outcome == 'failure'`.
- `README.md` **Inputs table rows only** (3 rows) — the Modes prose is A6's.

### Worktree split

| Slice / branch | Owns (exclusive) | Depends on |
|---|---|---|
| A2 `chore/dependabot-groups` | `.github/dependabot.yml` | — |
| A3 `ci/shellcheck-actionlint` | `.github/workflows/test.yaml` (or new `lint.yaml`), `.github/scripts/*.sh`, minimal quoting fixes in `scripts/*.sh` | — (merges before A4; A4 rebases) |
| A4 `feat/source-pat-github-target` | `scripts/mirror.sh`, `tests/unit/test_mirror.bats`, `action.yaml`, `.github/workflows/integration.yaml`, README **Inputs rows only** | none for code; rebases onto A3 |
| A5 `feat/hub-github-target` | `.github/workflows/mirror-all.yaml`, `config/repos.yaml` header | rebases onto A4 before its dispatch check |
| A6 `docs/mirror-modes` | README **Usage → Modes** + masking claim + badges/pin, `CHANGELOG.md`, `pyproject.toml` bumpversion search (if the dry-run needs it) | merges after A4 (docs describe shipped inputs) |
| A7 `docs/readme-canon-33` | README structure (canon), new `CONTRIBUTING.md` | data gate only |
| A8 `ci/reusable-release-36` | thin caller workflows | data gate only |

Only A4 owns `scripts/mirror.sh` + `test_mirror.bats` → no two worktrees edit the module. README is
touched by A4 (Inputs rows), A6 (Modes, badges), A7 (structure) in different regions — rebase, don't
coordinate.

## Remaining work (the ONE table)

Gate: `agent` = runs unattended · `owner` = needs the owner · `data` = needs an external fact/state.
Strike the row in the PR that ships it; append `— PR #n`.

| ID | Item | Gate | Branch / where | Done-when |
|---|---|---|---|---|
| P0 | Unattended-run prerequisite: shell works without permission prompts; before running any unfamiliar test suite's setup/fixture code, read it for side effects on shared/global state first | agent | local | **DONE — PR #40** |
| A0 | Materialize this plan; file tracking issue; write the issue # into Status | agent | main thread, `docs/arc-0001-plan` | **DONE — issue #41, PR TBD** |
| A1 | Squash-merge dependabot PRs #38, #39 | agent (authorized by plan approval) | main thread | |
| A2 | Dependabot `groups:` — one weekly group `github-actions-minor-patch` (`applies-to: version-updates`, `update-types: [minor, patch]`, `patterns: ["*"]`); majors stay ungrouped; default `open-pull-requests-limit` | agent | `chore/dependabot-groups` | **SHIPPED — PR #44**; observe once post-merge: next dependabot run opens ≤1 grouped PR |
| A3 | Add shellcheck + actionlint to CI. Prefer no marketplace-action pin where a direct install works (smaller supply-chain surface): `sudo apt-get install -y shellcheck` if not already preinstalled on `ubuntu-latest` (fetch/confirm live) and `actionlint` via its official install script or a pinned `docker run rhysd/actionlint:<tag>` (fetch current tag live — **UNVERIFIED until fetched**, don't guess a version); fix findings in `scripts/*.sh`, `.github/scripts/*.sh` — expect at least `cd "$CLONE_DIR"` without `\|\| exit` (SC2164) at mirror.sh:71 (moot once A4's `trap` lands — sequence A3 first, then A4 rebases and re-checks); README Development lists the local commands | agent | `ci/shellcheck-actionlint` | new CI steps green on the PR; `shellcheck`/`actionlint` clean locally |
| A4 | Feature core: RED tests 1-10 → GREEN changes (both tables above): `source_pat`, `github_url`/`github_pat`, PAT charset validation, self-clobber guard (https-form only), add-mask fix, argv-safe scrub, disk-residue scrub (`remote set-url`), `trap` cleanup, `credential.helper=`; `action.yaml` inputs/env; `integration.yaml` steps 2-4; README Inputs rows | agent | `feat/source-pat-github-target` | tests 1-10 RED then GREEN; 14 existing green; `TMPDIR=/tmp bats tests/unit/` + shellcheck clean; integration job shows steps 1-4 green (or the `x-access-token` decision recorded); PR merged |
| A5 | Hub wiring: gate all three PATs on their URLs (fixes shipped bug), host-derived `source_pat` reusing the same three secrets, `github_url: ${{ matrix.repo.github }}`, `permissions: contents: read`; `repos.yaml` header documents `github`. **Syntax proof before merge:** on the branch, temporarily swap `uses: …@v0` → `actions/checkout@v6` + `uses: ./`, two dummy entries in `repos.yaml`, `unset GH_TOKEN GITHUB_TOKEN; gh workflow run mirror-all.yaml --ref <branch>`; reaching `mirror.sh`'s config error / clone failure proves both expressions parsed; revert swap + config before merge | agent | `feat/hub-github-target` | `actionlint` clean; branch dispatch reached `mirror.sh` (run URL in PR); `yq -o=json config/repos.yaml` is `[]` again; PR merged (dormant until B3/B4) |
| A6 | README "Modes" section (push / invert / router — one `@v0` YAML example each; "GitHub target must pre-exist and be unprotected; `--mirror` force-updates refs"; note the guard is https-form only); README masking claim made true; badge MIT→Apache-2.0; usage pin `@v1`→ the tag that exists (`git ls-remote --tags origin`); repos.yaml is a trust boundary (see Watch-outs) noted in README/CONTRIBUTING; CHANGELOG `[Unreleased]` `### Added` (3 inputs, guard, hub `github` field, lint gates, dependabot groups) + `### Fixed` (add-mask, hub PAT gating, credential-on-disk residue) + drop stale test counts; **pre-stage B4**: `uv run bump-my-version bump minor --dry-run --verbose` — fix CHANGELOG shape or `pyproject.toml` search pattern until exit 0 | agent | `docs/mirror-modes` | **SHIPPED — PR #48**; lint-md-links green; dry-run exit 0 (output pasted in PR) |
| A7 | Issue #33 README canon: apply the itemized checklist from the #33 comment (badge order/colour, section renames, Why/Refs, Development → `CONTRIBUTING.md`) | data → agent | `docs/readme-canon-33` | canon final (qte77/qte77#124 + #126 closed/merged via `gh issue view`); every checklist item ticked; #33 closed by PR |
| A8 | Issue #36: thin `uses:` callers for `qte77/.github` bump/tag/publish reusable workflows | data → agent | `ci/reusable-release-36` | qte77/.github#33 merged (re-poll `gh pr view 33 --repo qte77/.github` at each arc touchpoint); callers added; `bump-and-release.yaml` retired or delegated; #36 closed |
| B1 | #7 GitLab account `qte77` + PAT (`write_repository`; add `read_repository` too since this same PAT doubles as the source credential when GitLab is a *source* — see the accepted single-secret-per-host tradeoff in Design decisions) | owner | gitlab.com | PAT value handed to B3 |
| B2 | #8 Codeberg account `qte77` + PAT (repo write; read too, same reason as B1) | owner | codeberg.org | PAT value handed to B3 |
| B3 | #9 secrets: `GITLAB_PAT`, `CODEBERG_PAT`, **`GH_TARGET_PAT`** (fine-grained GitHub PAT, `contents: read+write` on the target repos only) — three secrets total, each doing double duty as source-read + target-write credential for its host | owner (values) → agent (`unset GH_TOKEN GITHUB_TOKEN; gh secret set NAME --repo qte77/gha-github-mirror-action`) | GitHub repo settings | `gh secret list` shows all three |
| B4 | Release so the hub's `@v0` sees the new inputs: dispatch `bump-and-release` with `minor` (0.1.0 → 0.2.0); pre-staged by A6's dry-run → pure "go" | owner-approve → agent (`unset GH_TOKEN GITHUB_TOKEN; gh workflow run bump-and-release.yaml -f bump_type=minor`) | GitHub Actions | tag `v0.2.0` exists, floating `v0` moved, release published |
| C1 | #10 single-repo hub test: one entry in `repos.yaml`, `gh workflow run mirror-all.yaml`, verify refs on GitLab/Codeberg | agent (after B1–B4) | `main` via PR | `git ls-remote` on both targets lists all source refs; run log shows `***`/masked, never a PAT |
| C2 | #11 full rollout: populate `repos.yaml` from `gh repo list qte77` (public first), dispatch, spot-check 3 repos | agent | PR + dispatch | hub run green for every matrix entry |
| C3 | Invert e2e: one entry with a GitLab/Codeberg *source* and a pre-created GitHub `github` target; dispatch; verify. (The self-clobber negative test already ran in A4/CI against the hub repo itself — no need to repeat it here against a real external source.) | data (external source repo + `GH_TARGET_PAT`) → agent | PR + dispatch | GitHub target has the source's refs |
| C4 | Close tracking issue + #7–#11; final progress report; migrate anything left to `docs/plans/0002-…` | agent | GitHub | no open row without a state; arc marked closed in Status |

**Deferred (with reason):** remove dead `GH_TOKEN`/`GITHUB_TOKEN` env from `action.yaml` (needs
`test_infra_files.bats` change; zero user value now — suggestion only) · implicit `source_pat`
default (YAGNI, see Design decisions) · escaping PAT specials in the `sed` (documented limitation;
real formats are safe) · generic N-target list input (YAGNI/AHA) · auto-creating missing target
repos (out of scope; document "target must pre-exist").

## Owner checkpoint (Phase B — one sitting, everything pre-staged by Phase A)

1. B1 + B2: create accounts/PATs (≈15 min).
2. B3: paste PAT values into the `gh secret set` commands the agent prints (never into chat/logs).
3. B4: say "go" for the release dispatch (dry-run already green from A6).

## Arc-start access checklist

- `gh` auth: keyring login `qte77` scopes `gist, read:org, repo, workflow` ✅ — unset **both**
  `GH_TOKEN` and `GITHUB_TOKEN` per call (see Status).
- Bash: `bats`/`git`/`gh`/file ops confirmed working (P0, PR #40). `shellcheck`/`actionlint`/`yq` not
  yet installed locally — A3 adds them to CI; install locally only if you want to run the Commands
  block's lint lines before A3 lands.
- Secrets: none set yet (B3). External accounts: none (B1, B2).

## Verification (end-to-end)

1. Unit: `TMPDIR=/tmp bats tests/unit/` — tests 1-10 fail before A4's GREEN commit, pass after; total
   count reported in CHANGELOG.
2. Lint: `shellcheck scripts/*.sh .github/scripts/*.sh`; `actionlint` — clean.
3. Wiring: `integration.yaml` on the A4 PR shows four steps: gitlab-path target; gitlab+github path
   targets with dummy `source_pat`; `github.token` self-source; a self-clobber negative run whose
   `outcome == 'failure'`. All four pass (the 4th "passes" by failing as expected).
4. Security: CI logs of A4/A5/C1/C3 runs contain no literal PAT/dummy value outside `::add-mask::`
   lines (and on real runs those are hidden by the runner); a masked `***` appears wherever a
   credentialed URL would have been printed; no `mirror-repo-*` temp dir survives a clone failure.
5. Hub: A5 branch dispatch reached `mirror.sh`; C1 run green; `git ls-remote <target>` ref list equals
   `git ls-remote <source>`.
6. Invert: C3 run green (negative-guard coverage already proven in A4/CI, not repeated here).
