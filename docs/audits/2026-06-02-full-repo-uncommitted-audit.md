# Full Repo And Uncommitted Changes Audit - 2026-06-02

## Verdict

Remediation for the listed findings is complete in this working tree. The three
behavior regressions found by the targeted audit harnesses were fixed and
covered by regression tests, and the stale security posture text was updated.

No live installs, real shell-profile edits, real macOS defaults, or workstation
package changes were performed.

## Scope Reviewed

Target: full repository plus all uncommitted and untracked changes on
`docs/mvp-status-sync`.

Modified files reviewed:

- `AGENTS.md`
- `README.md`
- `catalog/tools.tsv`
- `docs/audits/2026-06-02-mvp-evaluation.md`
- `docs/rig-v1-spec.md`
- `install.sh`
- `lib/rig/catalog.sh`
- `lib/rig/common.sh`
- `lib/rig/doctor.sh`
- `lib/rig/plan.sh`
- `rig`
- `tests/run-tests.sh`

Untracked files reviewed:

- `lib/rig/apply.sh`
- `lib/rig/brew.sh`
- `lib/rig/config.sh`
- `lib/rig/prompts.sh`
- `lib/rig/shell.sh`

## Checks Performed

Passed:

- `for f in install.sh rig lib/rig/*.sh scripts/*.sh tests/*.sh; do bash -n "$f"; done`
- `bash tests/run-tests.sh`
- `./scripts/validate-catalog.sh`
- `./rig dry-run --select vscode,chrome,node-npm --defaults finder-show-hidden-files`
- `./install.sh --dry-run`
- `shellcheck install.sh rig lib/rig/*.sh scripts/*.sh tests/*.sh`
- `actionlint .github/workflows/*.yml`
- `git diff --check`

Passed targeted hermetic checks:

- fake external installer replay captured `nvm`, Bun installer, and `tenv` calls;
- temp-`HOME` dry-run left no config state;
- glob-heavy selections were rejected literally;
- Homebrew catalog metadata checked with temporary `HOMEBREW_CACHE`.

Added and passed during remediation:

- no-argument `rig install` with plain-Bash prompts, fake Darwin, temp `HOME`,
  and no selections writes config without hitting unbound plan globals;
- `./rig dry-run --select node-npm=lts` renders `node-npm nvm lts`;
- `rig install --from-config --brewfile <path> --install-plan <path>` succeeds
  on a clean temp config dir with fake `brew`.

Skipped:

- Docker Bash supplement. `bash:3.2` and `bash:latest` were not present locally;
  no image pull was performed during this read-only audit.

## Findings

### 1. High: `rig install` Interactive Path Crashes Before Config Write

- Status: Fixed in working tree.
- Location: `rig:36`, `lib/rig/plan.sh:602`
- Confidence: High
- Evidence: the no-argument `rig install` path bypasses `rig_parse_plan_args`,
  which is the only place `RIG_PLAN_BREWFILE`, `RIG_PLAN_INSTALL_PLAN`, and
  `RIG_PLAN_AUTO_UPDATE` are initialized. A hermetic harness failed with
  `lib/rig/plan.sh: line 602: RIG_PLAN_BREWFILE: unbound variable`.
- Trigger: a user runs the documented default flow, `rig install`.
- Impact: interactive install is unusable. After fixing the first unbound
  variable, `RIG_PLAN_AUTO_UPDATE` can still crash later when auto-update remains
  at the default `no`.
- Recommendation: initialize plan globals through a shared reset/init function
  before both parsed and interactive paths, or route the no-argument install path
  through the same parser defaults.
- Resolution: added `rig_reset_plan_globals` and call it from both parsed plan
  args and interactive selection.
- Verification: `tests/run-tests.sh` now runs no-argument `rig install` with
  plain-Bash prompt input, fake Darwin, and temp `HOME`.

### 2. Medium: `--select id=version` Validates But Drops The Requested Version

- Status: Fixed in working tree.
- Location: `lib/rig/plan.sh:173`, `lib/rig/plan.sh:570`
- Confidence: High
- Evidence: `rig_collect_selected_tools` updates `version_map`, but it is called
  inside command substitution, so the update is lost. Repro:
  `./rig dry-run --select node-npm=lts` outputs `node-npm nvm latest
  Node.js/npm`; `--version node-npm=lts` outputs `lts`.
- Trigger: a user follows the help text saying `--select` accepts optional
  `id=version`.
- Impact: explicit version choices can install or preview the wrong runtime
  version.
- Recommendation: parse `id=version` in the parent scope before command
  substitution, or remove/reject that syntax and require `--version`.
- Resolution: parse inline `--select id=version` values into the version map in
  the parent scope before collecting selected tool IDs.
- Verification: `tests/run-tests.sh` asserts `./rig dry-run --select
  node-npm=lts` renders `node-npm nvm lts`.

### 3. Medium: Bring-Your-Own Brewfile/Install-Plan Replay Is Blocked On Clean Config

- Status: Fixed in working tree.
- Location: `lib/rig/plan.sh:821`, `docs/rig-v1-spec.md:192`
- Confidence: High
- Evidence: `rig install --from-config --brewfile /tmp/Brewfile --install-plan
  /tmp/install-plan.tsv` fails with `no rig config found under ...` because
  `rig_config_exists` runs before path overrides are applied.
- Trigger: automation uses user-supplied config files on a clean machine.
- Impact: a spec-promised non-interactive replay mode cannot run unless the
  default `~/.config/rig` already exists.
- Recommendation: apply path overrides before the existence check, and treat
  provided readable override files as valid config input.
- Resolution: apply path overrides before from-config existence checks and make
  config existence use the effective Brewfile/install-plan/defaults paths.
- Verification: `tests/run-tests.sh` covers temp `HOME` with no `.config/rig`,
  custom Brewfile/install-plan paths, fake `brew`, and `rig install
  --from-config`.

### 4. Low: `SECURITY.md` Still Describes Install Surfaces As Inactive

- Status: Fixed in working tree.
- Location: `SECURITY.md:13`
- Confidence: High
- Evidence: it says real installs, `brew bundle`, config writes, shell edits, and
  macOS defaults "are not active yet," while README/spec now say those paths are
  implemented.
- Impact: public security guidance points reporters and reviewers at the wrong
  active attack surfaces.
- Recommendation: update the security posture section to match the v1 install
  behavior and explicitly list active apply surfaces.
- Resolution: updated `SECURITY.md` to list the active bootstrap, dry-run,
  config-write, Homebrew Bundle, install-plan, shell-block, macOS defaults,
  auto-update, and self-update surfaces.
- Verification: documentation review against `README.md` and `docs/rig-v1-spec.md`.

## Needs Verification

- Real workstation install/apply behavior was intentionally not exercised.
- Docker Linux/Bash supplement was not run because no suitable image was present
  locally and no image pull was performed during the read-only audit.
