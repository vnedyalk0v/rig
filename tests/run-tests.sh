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

out="$TEST_TMP/dry-run.out"
run_capture "$out" ./rig dry-run --select vscode,chrome,node-npm --defaults finder-show-hidden-files
assert_success "$?" "rig dry-run succeeds"
assert_contains "$out" "# Brewfile preview" "dry-run prints Brewfile section"
assert_contains "$out" "cask \"visual-studio-code\"" "dry-run includes VS Code cask"
assert_contains "$out" "cask \"google-chrome\"" "dry-run includes Chrome cask"
assert_contains "$out" "# External install plan preview" "dry-run prints external plan section"
assert_contains "$out" "node-npm	nvm	latest	Node.js/npm" "dry-run includes Node external plan"
assert_contains "$out" "# macOS defaults preview" "dry-run prints macOS defaults section"
assert_contains "$out" "defaults write com.apple.finder AppleShowAllFiles -bool true" "dry-run includes selected Finder default"
assert_contains "$out" "# Shell/profile edits preview" "dry-run prints shell edits section"

out="$TEST_TMP/install-dry-run.out"
run_capture "$out" ./rig install --dry-run --select vscode
assert_success "$?" "rig install --dry-run succeeds"
assert_contains "$out" "cask \"visual-studio-code\"" "install --dry-run delegates to dry-run"

out="$TEST_TMP/install-real.out"
run_capture "$out" ./rig install
assert_failure "$?" "rig install without dry-run is deferred"
assert_contains "$out" "real installs are deferred in this MVP" "deferred install message is clear"

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
run_capture "$out" ./rig dry-run --select does-not-exist
assert_failure "$?" "dry-run rejects unknown tool ids"
assert_contains "$out" "unknown catalog id: does-not-exist" "unknown tool id is reported"

out="$TEST_TMP/glob-selection.out"
run_capture "$out" ./rig dry-run --select '*'
assert_failure "$?" "dry-run rejects glob characters without expanding them"
assert_contains "$out" "invalid catalog id: *" "glob selection is reported literally"

bootstrap_home="$TEST_TMP/bootstrap-home"
mkdir -p "$bootstrap_home"
out="$TEST_TMP/bootstrap-dry-run.out"
HOME="$bootstrap_home" run_capture "$out" ./install.sh --dry-run
assert_success "$?" "install.sh --dry-run succeeds"
assert_contains "$out" "Dry run: no files will be created or changed" "bootstrap dry-run states no mutation"
assert_contains "$out" "$bootstrap_home/.local/share/rig" "bootstrap dry-run shows clone path"
if [ -e "$bootstrap_home/.local" ]; then
  fail "install.sh --dry-run does not create HOME state"
else
  pass "install.sh --dry-run does not create HOME state"
fi

out="$TEST_TMP/bootstrap-invalid-branch.out"
run_capture "$out" ./install.sh --dry-run --branch -bad
assert_failure "$?" "install.sh rejects option-like branch names"
assert_contains "$out" "invalid branch name: -bad" "invalid branch name is reported"

out="$TEST_TMP/bootstrap-invalid-repo-url.out"
run_capture "$out" ./install.sh --dry-run --repo-url 'ext::sh -c bad'
assert_failure "$?" "install.sh rejects unsafe repo URL transports"
assert_contains "$out" "invalid repo URL: ext::sh -c bad" "invalid repo URL is reported"

if [ "$failures" -eq 0 ]; then
  printf 'All tests passed\n'
  exit 0
fi

printf '%s test(s) failed\n' "$failures"
exit 1
