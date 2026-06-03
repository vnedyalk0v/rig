# Apple Silicon GitHub Actions Runners

Date: 2026-06-03

## Verdict

`rig` can use GitHub-hosted Apple Silicon macOS runners for CI and targeted
end-to-end testing. The repository is currently public (`vnedyalk0v/rig`), so
standard GitHub-hosted runners are free for this project. Use standard arm64
macOS labels, not Intel or larger-runner labels.

Best default for this project:

```yaml
runs-on: macos-15
```

`macos-latest` is also listed as arm64 today, but an explicit `macos-15` label
is better for a safety-sensitive bootstrap tool because it avoids silent OS
image changes when GitHub moves the `latest` alias.

## Current GitHub Runner Facts

GitHub's current hosted-runner reference lists these standard public macOS
Apple Silicon labels:

- `macos-latest`
- `macos-14`
- `macos-15`
- `macos-26`

Those labels run on arm64 macOS runners with 3 M1 CPU cores, 7 GB RAM, and
14 GB SSD in the public runner table.

GitHub also lists Intel macOS labels such as `macos-15-intel` and
`macos-26-intel`. Do not use those for the Apple Silicon path.

Avoid larger-runner labels such as `macos-15-large`, `macos-15-xlarge`, or
similar `large` / `xlarge` variants. GitHub's billing docs say larger runners
are always charged for, even in public repositories.

## Repo Fit

Apple Silicon runners are a good fit for `rig` because the project is
macOS-only and the spec explicitly depends on:

- `/bin/bash` 3.2-compatible shell code;
- the Apple Silicon Homebrew prefix, `/opt/homebrew`;
- real `uname -s` macOS behavior;
- real shell profile and Homebrew behavior on macOS;
- arm64 package availability through Homebrew and vendor installers.

They are not a perfect "brand-new Mac" substitute. GitHub runner images already
include many tools and preinstalled state. The runner is useful for macOS and
arm64 integration, but not for proving that every dependency is absent on a
clean retail machine.

## Recommended CI Shape

Use three layers instead of making every pull request perform a heavy install.

### 1. Required Apple Silicon Dry-Run Smoke

Implemented as the `Apple Silicon dry-run smoke` job in
`.github/workflows/apple-silicon-smoke.yml`. It runs on every pull request and
push to `dev` / `main`, on a weekly schedule, and through `workflow_dispatch`
for explicit reruns.

Purpose:

- prove the shell runs on real macOS arm64;
- prove dry-run stays side-effect free;
- run the existing local validation surface, including regression tests that
  cover temporary-home config generation.

Best practices:

- use `runs-on: macos-15`;
- assert `uname -s` is `Darwin`;
- assert `uname -m` is `arm64`;
- use a temporary `HOME` under `$RUNNER_TEMP` for commands that may write state;
- keep `permissions: contents: read`;
- do not use `pull_request_target`;
- pin third-party actions to full commit SHAs;
- set `persist-credentials: false` on `actions/checkout`;
- set a short `timeout-minutes`, for example 20.
- do not use path filters if the job is configured as a required check, because
  skipped required checks can block pull requests.

Useful command shape:

```bash
test "$(uname -s)" = "Darwin"
test "$(uname -m)" = "arm64"
/bin/bash --version | head -n 1
sw_vers

export HOME="$RUNNER_TEMP/rig-dry-run-home"
export RIG_CONFIG_DIR="$HOME/.config/rig"
mkdir -p "$HOME"

for f in install.sh rig lib/rig/*.sh scripts/*.sh tests/*.sh; do
  bash -n "$f"
done
bash tests/run-tests.sh
./scripts/validate-catalog.sh
./rig dry-run --select vscode,chrome,node-npm --defaults finder-show-hidden-files
./install.sh --dry-run
test ! -e "$RIG_CONFIG_DIR"
test ! -e "$HOME/.local/share/rig"
test ! -e "$HOME/.local/bin/rig"
git diff --check
```

If `shellcheck` or `actionlint` is not already present on the runner, install
only those validation tools through Homebrew in the smoke job. Keep this
separate from testing `rig` installs so validator setup does not hide product
behavior.

Required CI intentionally uses dry-run product commands only. It does not run
real `brew bundle` installs or replay external installers.

### 2. Automatic Apple Silicon Install Smoke

Implemented as the `Apple Silicon install smoke` job in
`.github/workflows/apple-silicon-smoke.yml`. It runs after the dry-run smoke on
pull requests and pushes to `dev` / `main`, on the weekly schedule, and through
`workflow_dispatch`.

Purpose:

- prove `rig install --write-config-only` creates real config in a temp home;
- prove `rig install --from-config` can invoke Homebrew Bundle on arm64;
- verify generated state is replayable.

Keep the required install selection intentionally small. Do not use the catalog
defaults for a real CI install, because the current defaults include GUI casks
such as Visual Studio Code and Google Chrome. Prefer a formula-only selection:

```bash
export HOME="$RUNNER_TEMP/rig-home"
export RIG_CONFIG_DIR="$HOME/.config/rig"
mkdir -p "$HOME"

./rig install --write-config-only --select gh
grep -F 'brew "gh"' "$RIG_CONFIG_DIR/Brewfile"
./rig install --from-config
brew bundle check --file="$RIG_CONFIG_DIR/Brewfile"
gh --version
```

Use these environment settings to reduce Homebrew noise and accidental update
work:

```bash
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export RIG_SKIP_HOMEBREW_INSTALL=yes
```

`RIG_SKIP_HOMEBREW_INSTALL=yes` is appropriate for this runner path because
GitHub macOS images already include Homebrew. It prevents the test from hiding
a missing runner Homebrew setup by running the Homebrew installer.

The implemented install smoke uses only the `gh` formula selection. It does not
install GUI casks, Mac App Store apps, external installers, or Homebrew
auto-update state.

### 3. Manual External Installer Smoke

Deferred for a future manual workflow. Run only on demand.

Purpose:

- verify one external installer path at a time, such as Bun, nvm, or tenv;
- keep network/vendor flakiness out of required PR checks;
- preserve reviewability for installer behavior.

Suggested examples:

- Bun path: `./rig install --write-config-only --select bun`, then
  `./rig install --from-config`, then verify `$HOME/.bun/bin/bun --version`.
- Node path: `./rig install --write-config-only --select node-npm=lts`, then
  verify nvm created a usable Node installation.
- tenv path: test one of `terraform`, `opentofu`, or `terragrunt`, not all
  three in the same required workflow.

Do not test `--auto-update` with real Homebrew auto-update in GitHub-hosted CI.
It can create launchd/background state and is not useful enough for a required
runner check. Keep auto-update coverage mocked or manual.

## Implemented Workflows

- `.github/workflows/apple-silicon-smoke.yml` runs both `Apple Silicon dry-run
  smoke` and `Apple Silicon install smoke` on `macos-15` for pull requests,
  pushes, the weekly schedule, and explicit reruns.

The workflow uses a pinned `actions/checkout` commit, sets
`persist-credentials: false`, and keeps `permissions: contents: read`.

After the workflow lands on `dev` and each job has reported at least once, the
rulesets should require these job names:

- `Apple Silicon dry-run smoke`
- `Apple Silicon install smoke`

## Operational Guardrails

- Keep the required Apple Silicon job short. macOS runner queues can be slower
  than Ubuntu runner queues.
- Use one arm64 macOS version in required PR CI. Use scheduled/manual matrix
  runs for broader compatibility, for example `macos-14` plus `macos-15`.
- Do not cache or restore a shared Homebrew state for product install tests.
  It can make install behavior less reproducible.
- Keep all real install tests in temporary `HOME` directories.
- Avoid GUI cask installs in required checks. They are slow, can be flaky, and
  do not add much signal for shell/config correctness.
- Avoid testing Mac App Store (`mas`) flows in GitHub-hosted CI. App Store
  authentication and Apple ID state are outside reliable runner automation.
- Do not rely on nested virtualization on arm64 macOS runners. GitHub documents
  nested virtualization as unsupported for arm64 macOS runners.
- Keep branch-policy workflows separate from product e2e workflows. Policy
  guards should continue to use trusted event metadata and not execute PR
  branch scripts.

## Sources

- GitHub Actions billing:
  <https://docs.github.com/en/billing/concepts/product-billing/github-actions>
- GitHub-hosted runners reference:
  <https://docs.github.com/en/actions/reference/runners/github-hosted-runners>
- Actions runner pricing:
  <https://docs.github.com/en/billing/reference/actions-runner-pricing>
- GitHub Actions runner images:
  <https://github.com/actions/runner-images>
