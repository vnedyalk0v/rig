#!/bin/bash

set -u

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT=${TMPDIR:-/tmp}
TEST_TMP=$(mktemp -d "${TMP_ROOT%/}/rig-tests.XXXXXX")

failures=0
doctor_home=

# shellcheck disable=SC2329
cleanup() {
  if [ "$doctor_home" != "" ] && [ -d "$doctor_home" ]; then
    chmod -R u+rwx "$doctor_home" 2>/dev/null || true
  fi
  rm -rf "$TEST_TMP"
}

trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1"
  failures=$((failures + 1))
}

pass() {
  printf 'ok - %s\n' "$1"
}

run_capture() {
  output_file=$1
  shift
  "$@" >"$output_file" 2>&1
}

assert_contains() {
  file=$1
  expected=$2
  name=$3
  if grep -F "$expected" "$file" >/dev/null 2>&1; then
    pass "$name"
  else
    printf '%s\n' "---- output ----"
    cat "$file"
    printf '%s\n' "----------------"
    fail "$name (missing: $expected)"
  fi
}

assert_not_contains() {
  file=$1
  unexpected=$2
  name=$3
  if grep -F "$unexpected" "$file" >/dev/null 2>&1; then
    printf '%s\n' "---- output ----"
    cat "$file"
    printf '%s\n' "----------------"
    fail "$name (unexpected: $unexpected)"
  else
    pass "$name"
  fi
}

assert_success() {
  status=$1
  name=$2
  if [ "$status" -eq 0 ]; then
    pass "$name"
  else
    fail "$name (exit $status)"
  fi
}

assert_failure() {
  status=$1
  name=$2
  if [ "$status" -ne 0 ]; then
    pass "$name"
  else
    fail "$name (expected failure)"
  fi
}

cd "$ROOT_DIR" || exit 1

fake_darwin_bin="$TEST_TMP/fake-darwin-bin"
fake_linux_bin="$TEST_TMP/fake-linux-bin"
mkdir -p "$fake_darwin_bin" "$fake_linux_bin"
cat >"$fake_darwin_bin/uname" <<'EOF'
#!/bin/bash
printf 'Darwin\n'
EOF
cat >"$fake_linux_bin/uname" <<'EOF'
#!/bin/bash
printf 'Linux\n'
EOF
chmod +x "$fake_darwin_bin/uname" "$fake_linux_bin/uname"

out="$TEST_TMP/pr-metadata-guard.out"
run_capture "$out" bash tests/pr-metadata-guard-tests.sh
assert_success "$?" "PR metadata guard tests pass"
assert_contains "$out" "All PR metadata guard tests passed" "PR metadata guard reports success"

out="$TEST_TMP/catalog-valid.out"
run_capture "$out" ./scripts/validate-catalog.sh
assert_success "$?" "catalog validation passes"
assert_contains "$out" "Catalog validation passed" "catalog validation reports success"

duplicate_catalog="$TEST_TMP/duplicate-tools.tsv"
{
  printf 'category\tid\tlabel\tkind\tpackage\tdefault\tdescription\tversion_strategy\tversions\tnotes\n'
  printf 'ide\tvscode\tVisual Studio Code\tcask\tvisual-studio-code\tyes\tEditor\thomebrew-latest\t\t\n'
  printf 'browser\tvscode\tDuplicate\tcask\tduplicate\tno\tDuplicate id\thomebrew-latest\t\t\n'
} >"$duplicate_catalog"
out="$TEST_TMP/catalog-duplicate.out"
run_capture "$out" ./scripts/validate-catalog.sh --tools "$duplicate_catalog"
assert_failure "$?" "catalog validation rejects duplicate ids"
assert_contains "$out" "duplicate id: vscode" "duplicate id is reported"

missing_description="$TEST_TMP/missing-description.tsv"
{
  printf 'category\tid\tlabel\tkind\tpackage\tdefault\tdescription\tversion_strategy\tversions\tnotes\n'
  printf 'ide\tvscode\tVisual Studio Code\tcask\tvisual-studio-code\tyes\t\thomebrew-latest\t\t\n'
} >"$missing_description"
out="$TEST_TMP/catalog-missing-description.out"
run_capture "$out" ./scripts/validate-catalog.sh --tools "$missing_description"
assert_failure "$?" "catalog validation rejects missing descriptions"
assert_contains "$out" "description is required" "missing description is reported"

out="$TEST_TMP/version.out"
run_capture "$out" ./rig version
assert_success "$?" "rig version succeeds"
assert_contains "$out" "rig 0.1.0" "rig version reports MVP version"

out="$TEST_TMP/list-ai.out"
run_capture "$out" ./rig list --category ai
assert_success "$?" "rig list category succeeds"
assert_contains "$out" "codex-cli" "AI category includes Codex CLI"
assert_not_contains "$out" "google-chrome" "AI category excludes browser tools"

out="$TEST_TMP/list-unknown-category.out"
run_capture "$out" ./rig list --category does-not-exist
assert_failure "$?" "rig list rejects unknown categories"
assert_contains "$out" "unknown category: does-not-exist" "unknown list category is reported"

out="$TEST_TMP/dry-run.out"
PATH="$fake_darwin_bin:$PATH" run_capture "$out" ./rig dry-run --select vscode,chrome,node-npm --defaults finder-show-hidden-files
assert_success "$?" "rig dry-run succeeds"
assert_contains "$out" "# Brewfile preview" "dry-run prints Brewfile section"
assert_contains "$out" "cask \"visual-studio-code\"" "dry-run includes VS Code cask"
assert_contains "$out" "cask \"google-chrome\"" "dry-run includes Chrome cask"
assert_contains "$out" "# External install plan preview" "dry-run prints external plan section"
assert_contains "$out" "node-npm	nvm	latest	Node.js/npm" "dry-run includes Node external plan"
assert_contains "$out" "# macOS defaults preview" "dry-run prints macOS defaults section"
assert_contains "$out" "defaults write com.apple.finder AppleShowAllFiles -bool true" "dry-run includes selected Finder default"
assert_contains "$out" "# Shell/profile edits preview" "dry-run prints shell edits section"

out="$TEST_TMP/dry-run-non-macos.out"
PATH="$fake_linux_bin:$PATH" RIG_LOGIN_SHELL=/bin/zsh run_capture "$out" ./rig dry-run --select vscode
assert_failure "$?" "rig dry-run fails clearly on non-macOS"
assert_contains "$out" "rig supports macOS only; detected Linux" "dry-run reports macOS-only guard"
assert_not_contains "$out" "cask \"visual-studio-code\"" "dry-run does not render a plan on non-macOS"

out="$TEST_TMP/dry-run-repeated-select.out"
PATH="$fake_darwin_bin:$PATH" run_capture "$out" ./rig dry-run --select vscode --select chrome
assert_failure "$?" "dry-run rejects repeated --select"
assert_contains "$out" "repeated --select is not supported" "repeated --select is reported"

out="$TEST_TMP/dry-run-repeated-defaults.out"
PATH="$fake_darwin_bin:$PATH" run_capture "$out" ./rig dry-run --defaults finder-show-hidden-files --defaults dock-autohide
assert_failure "$?" "dry-run rejects repeated --defaults"
assert_contains "$out" "repeated --defaults is not supported" "repeated --defaults is reported"

out="$TEST_TMP/dry-run-repeated-category.out"
PATH="$fake_darwin_bin:$PATH" run_capture "$out" ./rig dry-run --category ide --category browser
assert_failure "$?" "dry-run rejects repeated --category"
assert_contains "$out" "repeated --category is not supported" "repeated --category is reported"

out="$TEST_TMP/dry-run-unknown-category.out"
PATH="$fake_darwin_bin:$PATH" run_capture "$out" ./rig dry-run --category does-not-exist
assert_failure "$?" "dry-run rejects unknown categories"
assert_contains "$out" "unknown category: does-not-exist" "unknown dry-run category is reported"

out="$TEST_TMP/install-dry-run.out"
PATH="$fake_darwin_bin:$PATH" run_capture "$out" ./rig install --dry-run --select vscode
assert_success "$?" "rig install --dry-run succeeds"
assert_contains "$out" "cask \"visual-studio-code\"" "install --dry-run delegates to dry-run"

out="$TEST_TMP/install-dry-run-non-macos.out"
PATH="$fake_linux_bin:$PATH" RIG_LOGIN_SHELL=/bin/zsh run_capture "$out" ./rig install --dry-run --select vscode
assert_failure "$?" "rig install --dry-run fails clearly on non-macOS"
assert_contains "$out" "rig supports macOS only; detected Linux" "install --dry-run reports macOS-only guard"
assert_not_contains "$out" "cask \"visual-studio-code\"" "install --dry-run does not render a plan on non-macOS"

out="$TEST_TMP/install-real.out"
PATH="$fake_darwin_bin:$PATH" run_capture "$out" ./rig install
assert_failure "$?" "rig install without dry-run is deferred"
assert_contains "$out" "real installs are deferred in this MVP" "deferred install message is clear"

out="$TEST_TMP/install-unknown-arg.out"
run_capture "$out" ./rig install --bogus
assert_failure "$?" "rig install rejects unknown arguments"
assert_contains "$out" "unknown install argument: --bogus" "unknown install argument is reported"

out="$TEST_TMP/install-help-anywhere.out"
run_capture "$out" ./rig install --select vscode --help
assert_success "$?" "rig install --help is honored in any position"
assert_contains "$out" "Usage: rig install" "install help is shown regardless of argument position"

out="$TEST_TMP/shell-edit-detection.out"
PATH="$fake_darwin_bin:$PATH" RIG_LOGIN_SHELL=/bin/zsh run_capture "$out" ./rig dry-run --select node-npm
assert_success "$?" "dry-run with version-manager selection succeeds"
assert_contains "$out" "Would add managed rig initialization block" "shell-edit detection fires for version-manager selection"

invalid_mas_catalog="$TEST_TMP/invalid-mas-tools.tsv"
{
  printf 'category\tid\tlabel\tkind\tpackage\tdefault\tdescription\tversion_strategy\tversions\tnotes\n'
  printf 'productivity\tbad-mas\tBad MAS\tmas\tnot-a-number\tno\tInvalid mas id\thomebrew-latest\t\t\n'
} >"$invalid_mas_catalog"
out="$TEST_TMP/catalog-invalid-mas.out"
run_capture "$out" ./scripts/validate-catalog.sh --tools "$invalid_mas_catalog"
assert_failure "$?" "catalog validation rejects non-numeric mas ids"
assert_contains "$out" "invalid mas id: not-a-number" "invalid mas id is reported"

fake_git_bin="$TEST_TMP/fake-git-bin"
fake_git_log="$TEST_TMP/self-update-git.log"
mkdir -p "$fake_git_bin"
cat >"$fake_git_bin/git" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >>"$fake_git_log"
exit 0
EOF
chmod +x "$fake_git_bin/git"

out="$TEST_TMP/self-update-help.out"
rm -f "$fake_git_log"
PATH="$fake_git_bin:$PATH" run_capture "$out" ./rig self-update --help
assert_success "$?" "rig self-update --help succeeds"
assert_contains "$out" "Usage: rig self-update" "self-update help is shown"
if [ -e "$fake_git_log" ]; then
  fail "rig self-update --help does not invoke git"
else
  pass "rig self-update --help does not invoke git"
fi

out="$TEST_TMP/self-update-unknown-arg.out"
rm -f "$fake_git_log"
PATH="$fake_git_bin:$PATH" run_capture "$out" ./rig self-update --bogus
assert_failure "$?" "rig self-update rejects unknown arguments"
assert_contains "$out" "unknown self-update argument: --bogus" "unknown self-update argument is reported"
if [ -e "$fake_git_log" ]; then
  fail "rig self-update unknown argument does not invoke git"
else
  pass "rig self-update unknown argument does not invoke git"
fi

out="$TEST_TMP/self-update-non-macos.out"
rm -f "$fake_git_log"
PATH="$fake_linux_bin:$fake_git_bin:$PATH" run_capture "$out" ./rig self-update
assert_failure "$?" "rig self-update fails clearly on non-macOS"
assert_contains "$out" "rig supports macOS only; detected Linux" "self-update reports macOS-only guard"
if [ -e "$fake_git_log" ]; then
  fail "rig self-update non-macOS guard does not invoke git"
else
  pass "rig self-update non-macOS guard does not invoke git"
fi

if [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
  doctor_home="$TEST_TMP/readonly-home"
  mkdir -p "$doctor_home"
  chmod 500 "$doctor_home"
  out="$TEST_TMP/doctor-readonly-home.out"
  HOME="$doctor_home" run_capture "$out" ./rig doctor
  assert_success "$?" "rig doctor warns but does not fail for read-only HOME in MVP"
  assert_contains "$out" "warning: HOME is not writable" "doctor reports read-only HOME warning"
  chmod 700 "$doctor_home"
else
  out="$TEST_TMP/doctor-non-macos.out"
  run_capture "$out" ./rig doctor
  assert_failure "$?" "rig doctor fails clearly on non-macOS"
  assert_contains "$out" "rig supports macOS only" "doctor reports macOS-only guard"
fi

out="$TEST_TMP/unknown-selection.out"
PATH="$fake_darwin_bin:$PATH" run_capture "$out" ./rig dry-run --select does-not-exist
assert_failure "$?" "dry-run rejects unknown tool ids"
assert_contains "$out" "unknown catalog id: does-not-exist" "unknown tool id is reported"

out="$TEST_TMP/glob-selection.out"
PATH="$fake_darwin_bin:$PATH" run_capture "$out" ./rig dry-run --select '*'
assert_failure "$?" "dry-run rejects glob characters without expanding them"
assert_contains "$out" "invalid catalog id: *" "glob selection is reported literally"

bootstrap_home="$TEST_TMP/bootstrap-home"
mkdir -p "$bootstrap_home"
out="$TEST_TMP/bootstrap-dry-run.out"
HOME="$bootstrap_home" PATH="$fake_darwin_bin:$PATH" run_capture "$out" ./install.sh --dry-run
assert_success "$?" "install.sh --dry-run succeeds"
assert_contains "$out" "Dry run: no files will be created or changed" "bootstrap dry-run states no mutation"
assert_contains "$out" "$bootstrap_home/.local/share/rig" "bootstrap dry-run shows clone path"
if [ -e "$bootstrap_home/.local" ]; then
  fail "install.sh --dry-run does not create HOME state"
else
  pass "install.sh --dry-run does not create HOME state"
fi

non_macos_bootstrap_home="$TEST_TMP/bootstrap-non-macos-home"
mkdir -p "$non_macos_bootstrap_home"
out="$TEST_TMP/bootstrap-dry-run-non-macos.out"
HOME="$non_macos_bootstrap_home" PATH="$fake_linux_bin:$PATH" run_capture "$out" ./install.sh --dry-run
assert_failure "$?" "install.sh --dry-run fails clearly on non-macOS"
assert_contains "$out" "rig supports macOS only; detected Linux" "bootstrap dry-run reports macOS-only guard"
assert_not_contains "$out" "rig bootstrap dry-run" "bootstrap dry-run does not render a plan on non-macOS"
if [ -e "$non_macos_bootstrap_home/.local" ]; then
  fail "install.sh non-macOS dry-run does not create HOME state"
else
  pass "install.sh non-macOS dry-run does not create HOME state"
fi

bootstrap_conflict_home="$TEST_TMP/bootstrap-conflict-home"
mkdir -p "$bootstrap_conflict_home/.local/bin"
printf 'existing rig command\n' >"$bootstrap_conflict_home/.local/bin/rig"
out="$TEST_TMP/bootstrap-command-conflict.out"
rm -f "$fake_git_log"
HOME="$bootstrap_conflict_home" PATH="$fake_darwin_bin:$fake_git_bin:$PATH" run_capture "$out" ./install.sh
assert_failure "$?" "install.sh rejects command-path conflicts before bootstrap"
assert_contains "$out" "already exists and is not a symlink" "bootstrap command-path conflict is reported"
if [ -e "$fake_git_log" ]; then
  fail "install.sh command-path conflict does not invoke git"
else
  pass "install.sh command-path conflict does not invoke git"
fi

out="$TEST_TMP/bootstrap-invalid-branch.out"
run_capture "$out" ./install.sh --dry-run --branch -bad
assert_failure "$?" "install.sh rejects option-like branch names"
assert_contains "$out" "invalid branch name: -bad" "invalid branch name is reported"

out="$TEST_TMP/bootstrap-invalid-repo-url.out"
run_capture "$out" ./install.sh --dry-run --repo-url 'ext::sh -c bad'
assert_failure "$?" "install.sh rejects unsafe repo URL transports"
assert_contains "$out" "invalid repo URL: ext::sh -c bad" "invalid repo URL is reported"

out="$TEST_TMP/sync-main-to-dev-pr-list.out"
run_capture "$out" grep -F "gh pr list --repo \"\$REPO\"" .github/workflows/sync-main-to-dev.yml
assert_success "$?" "sync workflow passes repo context to gh pr list"

out="$TEST_TMP/sync-main-to-dev-pr-create.out"
run_capture "$out" grep -F "gh pr create --repo \"\$REPO\"" .github/workflows/sync-main-to-dev.yml
assert_success "$?" "sync workflow passes repo context to gh pr create"

if [ "$failures" -eq 0 ]; then
  printf 'All tests passed\n'
  exit 0
fi

printf '%s test(s) failed\n' "$failures"
exit 1
