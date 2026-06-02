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
  local output_file
  output_file=$1
  shift
  "$@" >"$output_file" 2>&1
  return $?
}

assert_contains() {
  local file expected name
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
  local file unexpected name
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
  local status name
  status=$1
  name=$2
  if [ "$status" -eq 0 ]; then
    pass "$name"
  else
    fail "$name (exit $status)"
  fi
}

assert_failure() {
  local status name
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
case "$1" in
  ""|-s)
    printf 'Darwin\n'
    ;;
  *)
    /usr/bin/uname "$@"
    ;;
esac
EOF
cat >"$fake_linux_bin/uname" <<'EOF'
#!/bin/bash
case "$1" in
  ""|-s)
    printf 'Linux\n'
    ;;
  *)
    /usr/bin/uname "$@"
    ;;
esac
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

out="$TEST_TMP/install-interactive-empty.out"
interactive_home="$TEST_TMP/interactive-home"
mkdir -p "$interactive_home"
# shellcheck disable=SC2016
PATH="$fake_darwin_bin:/usr/bin:/bin" HOME="$interactive_home" RIG_CONFIG_DIR="$interactive_home/.config/rig" run_capture "$out" bash -c '
  i=0
  while [ "$i" -lt 40 ]; do
    printf "\n"
    i=$((i + 1))
  done | ./rig install
'
assert_success "$?" "rig install interactive default path succeeds with no selections"
assert_contains "$out" "Wrote rig config" "interactive install writes config"
assert_success "$([ -f "$interactive_home/.config/rig/Brewfile" ] && echo 0 || echo 1)" "interactive install creates Brewfile"

out="$TEST_TMP/install-dry-run-non-macos.out"
PATH="$fake_linux_bin:$PATH" RIG_LOGIN_SHELL=/bin/zsh run_capture "$out" ./rig install --dry-run --select vscode
assert_failure "$?" "rig install --dry-run fails clearly on non-macOS"
assert_contains "$out" "rig supports macOS only; detected Linux" "install --dry-run reports macOS-only guard"
assert_not_contains "$out" "cask \"visual-studio-code\"" "install --dry-run does not render a plan on non-macOS"

out="$TEST_TMP/install-write-config.out"
config_home="$TEST_TMP/config-home"
mkdir -p "$config_home"
PATH="$fake_darwin_bin:$PATH" HOME="$config_home" RIG_CONFIG_DIR="$config_home/.config/rig" run_capture "$out" ./rig install --write-config-only --select vscode,chrome --defaults finder-show-hidden-files
assert_success "$?" "rig install --write-config-only succeeds"
assert_contains "$out" "Wrote rig config" "write-config-only reports config write"
assert_success "$([ -f "$config_home/.config/rig/Brewfile" ] && echo 0 || echo 1)" "Brewfile is created"
assert_success "$([ -f "$config_home/.config/rig/install-plan.tsv" ] && echo 0 || echo 1)" "install-plan.tsv is created"
assert_success "$([ -f "$config_home/.config/rig/macos-defaults.sh" ] && echo 0 || echo 1)" "macos-defaults.sh is created"

brewfile_content=$(cat "$config_home/.config/rig/Brewfile")
case "$brewfile_content" in
  *'cask "visual-studio-code"'*) pass "Brewfile contains VS Code" ;;
  *) fail "Brewfile contains VS Code" ;;
esac

out="$TEST_TMP/install-version.out"
PATH="$fake_darwin_bin:$PATH" HOME="$config_home" RIG_CONFIG_DIR="$config_home/.config/rig" run_capture "$out" ./rig install --write-config-only --select node-npm --version node-npm=lts
assert_success "$?" "rig install --write-config-only with version succeeds"
install_plan_file="$config_home/.config/rig/install-plan.tsv"
out="$TEST_TMP/install-plan-content.out"
cp "$install_plan_file" "$out"
assert_contains "$out" $'node-npm\tnvm\tnvm\tlts\t' "install plan records requested version"

out="$TEST_TMP/install-from-config-missing.out"
PATH="$fake_darwin_bin:$PATH" HOME="$TEST_TMP/empty-home" RIG_CONFIG_DIR="$TEST_TMP/empty-home/.config/rig" run_capture "$out" ./rig install --from-config
assert_failure "$?" "rig install --from-config fails without config"
assert_contains "$out" "no rig config found" "from-config reports missing config"

fake_brew_bin="$TEST_TMP/fake-brew-bin"
fake_brew_log="$TEST_TMP/brew.log"
mkdir -p "$fake_brew_bin"
cat >"$fake_brew_bin/brew" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >>"$fake_brew_log"
case "\$1:\$2:\$3" in
  shellenv)
    printf 'export PATH=/fake/brew/bin:\$PATH\n'
    ;;
  bundle:install:*)
    exit 0
    ;;
  update|upgrade)
    exit 0
    ;;
  tap)
    exit 0
    ;;
  autoupdate:*)
    exit 0
    ;;
  install)
    exit 0
    ;;
esac
exit 0
EOF
chmod +x "$fake_brew_bin/brew"
rm -f "$fake_brew_log"
apply_home="$TEST_TMP/apply-home"
mkdir -p "$apply_home/.config/rig"
printf 'cask "visual-studio-code"\n' >"$apply_home/.config/rig/Brewfile"
printf 'id\tstrategy\tpackage\tversion\tlabel\n' >"$apply_home/.config/rig/install-plan.tsv"
printf '#!/bin/bash\n' >"$apply_home/.config/rig/macos-defaults.sh"
PATH="$fake_darwin_bin:$fake_brew_bin:$PATH" HOME="$apply_home" RIG_CONFIG_DIR="$apply_home/.config/rig" RIG_SKIP_HOMEBREW_INSTALL=yes run_capture "$out" ./rig install --from-config
assert_success "$?" "rig install --from-config succeeds with mock brew"
assert_contains "$fake_brew_log" "bundle install --file=" "from-config invokes brew bundle"

override_home="$TEST_TMP/override-home"
override_config="$TEST_TMP/override-config"
override_brewfile="$override_config/Brewfile"
override_install_plan="$override_config/install-plan.tsv"
mkdir -p "$override_home" "$override_config"
printf 'cask "visual-studio-code"\n' >"$override_brewfile"
printf 'id\tstrategy\tpackage\tversion\tlabel\n' >"$override_install_plan"
out="$TEST_TMP/install-from-config-overrides.out"
rm -f "$fake_brew_log"
PATH="$fake_darwin_bin:$fake_brew_bin:$PATH" HOME="$override_home" RIG_CONFIG_DIR="$override_home/.config/rig" RIG_SKIP_HOMEBREW_INSTALL=yes run_capture "$out" ./rig install --from-config --brewfile "$override_brewfile" --install-plan "$override_install_plan"
assert_success "$?" "rig install --from-config accepts override files on clean config"
assert_contains "$fake_brew_log" "bundle install --file=$override_brewfile" "from-config override uses provided Brewfile"

out="$TEST_TMP/install-unknown-arg.out"
PATH="$fake_darwin_bin:$PATH" run_capture "$out" ./rig install --bogus
assert_failure "$?" "rig install rejects unknown arguments"
assert_contains "$out" "unknown install argument: --bogus" "unknown install argument is reported"

out="$TEST_TMP/install-unknown-arg-non-macos.out"
PATH="$fake_linux_bin:$PATH" run_capture "$out" ./rig install --bogus
assert_failure "$?" "rig install guards non-macOS before install argument parsing"
assert_contains "$out" "rig supports macOS only; detected Linux" "install unknown argument reports macOS guard first on non-macOS"
assert_not_contains "$out" "unknown install argument: --bogus" "install unknown argument does not parse unsupported platform"

out="$TEST_TMP/dry-run-version.out"
PATH="$fake_darwin_bin:$PATH" run_capture "$out" ./rig dry-run --select node-npm --version node-npm=lts
assert_success "$?" "rig dry-run with version succeeds"
assert_contains "$out" "node-npm	nvm	lts	Node.js/npm" "dry-run honors version flag"

out="$TEST_TMP/dry-run-select-inline-version.out"
PATH="$fake_darwin_bin:$PATH" run_capture "$out" ./rig dry-run --select node-npm=lts
assert_success "$?" "rig dry-run with inline select version succeeds"
assert_contains "$out" "node-npm	nvm	lts	Node.js/npm" "dry-run honors inline select version"

out="$TEST_TMP/dry-run-invalid-version.out"
PATH="$fake_darwin_bin:$PATH" run_capture "$out" ./rig dry-run --select node-npm --version node-npm=badversion
assert_failure "$?" "rig dry-run rejects unsupported version"
assert_contains "$out" "unsupported version for node-npm" "invalid version is reported"

out="$TEST_TMP/install-from-config-select.out"
PATH="$fake_darwin_bin:$PATH" HOME="$apply_home" RIG_CONFIG_DIR="$apply_home/.config/rig" run_capture "$out" ./rig install --from-config --select vscode
assert_failure "$?" "rig install --from-config rejects --select"
assert_contains "$out" "cannot be combined with --select" "from-config select conflict is reported"

out="$TEST_TMP/install-from-config-write-config.out"
PATH="$fake_darwin_bin:$PATH" HOME="$apply_home" RIG_CONFIG_DIR="$apply_home/.config/rig" run_capture "$out" ./rig install --from-config --write-config-only
assert_failure "$?" "rig install --from-config rejects --write-config-only"
assert_contains "$out" "cannot be combined with --write-config-only" "from-config write-config conflict is reported"

out="$TEST_TMP/install-auto-update.out"
rm -f "$fake_brew_log"
PATH="$fake_darwin_bin:$fake_brew_bin:$PATH" HOME="$apply_home" RIG_CONFIG_DIR="$apply_home/.config/rig" RIG_SKIP_HOMEBREW_INSTALL=yes run_capture "$out" ./rig install --from-config --auto-update
assert_success "$?" "rig install --from-config --auto-update succeeds with mock brew"
assert_contains "$fake_brew_log" "autoupdate start" "auto-update invokes brew autoupdate start"

out="$TEST_TMP/dry-run-auto-update-preview.out"
PATH="$fake_darwin_bin:$PATH" run_capture "$out" ./rig dry-run --select vscode --auto-update
assert_success "$?" "rig dry-run with auto-update succeeds"
assert_contains "$out" "Auto-update preview" "dry-run shows auto-update preview"
assert_contains "$out" "homebrew-autoupdate" "dry-run mentions homebrew-autoupdate"

out="$TEST_TMP/install-help-auto-update.out"
run_capture "$out" ./rig install --help
assert_success "$?" "rig install --help succeeds"
assert_contains "$out" "[--auto-update]" "install help includes auto-update flag"

injection_marker="$TEST_TMP/injection-marker"
rm -f "$injection_marker"
out="$TEST_TMP/heredoc-injection-version.out"
PATH="$fake_darwin_bin:$PATH" run_capture "$out" ./rig dry-run --select node-npm --version "node-npm=lts\$(touch $injection_marker)"
assert_failure "$?" "dry-run rejects malicious version injection payload"
if [ -e "$injection_marker" ]; then
  fail "dry-run does not execute command substitution in --version"
else
  pass "dry-run does not execute command substitution in --version"
fi

out="$TEST_TMP/from-config-dry-run.out"
PATH="$fake_darwin_bin:$PATH" HOME="$apply_home" RIG_CONFIG_DIR="$apply_home/.config/rig" run_capture "$out" ./rig install --from-config --dry-run
assert_success "$?" "rig install --from-config --dry-run succeeds"
assert_contains "$out" 'cask "visual-studio-code"' "from-config dry-run previews saved Brewfile"

tampered_home="$TEST_TMP/tampered-home"
mkdir -p "$tampered_home/.config/rig"
printf 'cask "visual-studio-code"\n' >"$tampered_home/.config/rig/Brewfile"
printf 'id\tstrategy\tpackage\tversion\tlabel\n' >"$tampered_home/.config/rig/install-plan.tsv"
printf 'node-npm\tevilmanager\tnvm\tlts\tNode.js/npm\n' >>"$tampered_home/.config/rig/install-plan.tsv"
printf '#!/bin/bash\n' >"$tampered_home/.config/rig/macos-defaults.sh"
out="$TEST_TMP/tampered-install-plan.out"
PATH="$fake_darwin_bin:$fake_brew_bin:$PATH" HOME="$tampered_home" RIG_CONFIG_DIR="$tampered_home/.config/rig" RIG_SKIP_HOMEBREW_INSTALL=yes run_capture "$out" ./rig install --from-config
assert_failure "$?" "rig install --from-config rejects tampered install plan"
assert_contains "$out" "strategy mismatch" "tampered install plan strategy mismatch is reported"

out="$TEST_TMP/interactive-selection-stub.out"
PATH="$fake_darwin_bin:$PATH" RIG_ROOT="$ROOT_DIR" bash -c '
  . "'"$ROOT_DIR"'/lib/rig/common.sh"
  . "'"$ROOT_DIR"'/lib/rig/catalog.sh"
  . "'"$ROOT_DIR"'/lib/rig/plan.sh"
  . "'"$ROOT_DIR"'/lib/rig/prompts.sh"
  rig_each_category() { printf "ide\n"; }
  rig_prompt_tools_for_category() { printf "vscode\n"; }
  rig_prompt_defaults() { return 0; }
  rig_prompt_auto_update() { printf "no\n"; }
  rig_validate_catalogs
  rig_run_interactive_selection
  printf "tools:%s" "$RIG_PLAN_SELECTED_TOOLS"
' >"$out" 2>&1
assert_success "$?" "interactive selection stub succeeds"
assert_contains "$out" "tools:vscode" "interactive selection stub selects vscode"

bootstrap_git_bin="$TEST_TMP/bootstrap-git-bin"
bootstrap_git_log="$TEST_TMP/bootstrap-git.log"
bootstrap_success_home="$TEST_TMP/bootstrap-success-home"
mkdir -p "$bootstrap_git_bin" "$bootstrap_success_home"
cat >"$bootstrap_git_bin/git" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >>"$bootstrap_git_log"
case "\$1" in
  clone)
    dest="\${@: -1}"
    mkdir -p "\$dest/.git"
    cp -R "$ROOT_DIR/rig" "$ROOT_DIR/lib" "$ROOT_DIR/catalog" "\$dest/" || exit 1
    exit 0
    ;;
  fetch|checkout|pull)
    exit 0
    ;;
esac
exit 0
EOF
chmod +x "$bootstrap_git_bin/git"
rm -f "$bootstrap_git_log"
out="$TEST_TMP/bootstrap-success.out"
HOME="$bootstrap_success_home" PATH="$fake_darwin_bin:$bootstrap_git_bin:$PATH" run_capture "$out" ./install.sh
assert_success "$?" "install.sh bootstrap succeeds with fake git"
assert_contains "$out" "rig command installed at" "bootstrap success reports installed command"
assert_success "$([ -L "$bootstrap_success_home/.local/bin/rig" ] && echo 0 || echo 1)" "bootstrap creates rig symlink"
assert_contains "$bootstrap_git_log" "clone" "bootstrap invokes git clone"

out="$TEST_TMP/shell-managed-block.out"
shell_profile="$TEST_TMP/shell-managed.zshrc"
: >"$shell_profile"
PATH="$fake_darwin_bin:$PATH" RIG_ROOT="$ROOT_DIR" bash -c '
  . "'"$ROOT_DIR"'/lib/rig/common.sh"
  . "'"$ROOT_DIR"'/lib/rig/shell.sh"
  rig_shell_apply_managed_block "'"$shell_profile"'"
  rig_shell_apply_managed_block "'"$shell_profile"'"
'
assert_success "$?" "shell managed block apply succeeds twice"
managed_block_count=$(grep -c '# >>> rig managed >>>' "$shell_profile" || true)
if [ "$managed_block_count" -eq 1 ]; then
  pass "shell managed block remains idempotent"
else
  fail "shell managed block remains idempotent (expected 1 block, got $managed_block_count)"
fi

out="$TEST_TMP/update-tools-help.out"
run_capture "$out" ./rig update-tools --help
assert_success "$?" "rig update-tools --help succeeds"
assert_contains "$out" "Usage: rig update-tools" "update-tools help is shown"

out="$TEST_TMP/update-tools.out"
rm -f "$fake_brew_log"
PATH="$fake_darwin_bin:$fake_brew_bin:$PATH" run_capture "$out" ./rig update-tools
assert_success "$?" "rig update-tools succeeds with mock brew"
assert_contains "$fake_brew_log" "update" "update-tools runs brew update"

out="$TEST_TMP/install-help-anywhere.out"
run_capture "$out" ./rig install --select vscode --help
assert_success "$?" "rig install --help is honored in any position"
assert_contains "$out" "Usage: rig install" "install help is shown regardless of argument position"

out="$TEST_TMP/emit-brewfile.out"
PATH="$fake_darwin_bin:$PATH" RIG_ROOT="$ROOT_DIR" RIG_LOGIN_SHELL=/bin/zsh bash -c '
  . "'"$ROOT_DIR"'/lib/rig/common.sh"
  . "'"$ROOT_DIR"'/lib/rig/catalog.sh"
  . "'"$ROOT_DIR"'/lib/rig/plan.sh"
  rig_validate_catalogs
  selected=$(rig_collect_selected_tools "vscode,chrome" "")
  rig_emit_brewfile_content "$selected"
' >"$TEST_TMP/emit-brewfile.out" 2>&1
assert_success "$?" "emit brewfile helper succeeds"
assert_contains "$TEST_TMP/emit-brewfile.out" "cask \"visual-studio-code\"" "emit helper includes VS Code"

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

invalid_tap_catalog="$TEST_TMP/invalid-tap-tools.tsv"
{
  printf 'category\tid\tlabel\tkind\tpackage\tdefault\tdescription\tversion_strategy\tversions\tnotes\n'
  printf 'infra\tbad-tap\tBad Tap\ttap-formula\tmissing-slash\tno\tInvalid tap formula\thomebrew-latest\t\t\n'
} >"$invalid_tap_catalog"
out="$TEST_TMP/catalog-invalid-tap.out"
run_capture "$out" ./scripts/validate-catalog.sh --tools "$invalid_tap_catalog"
assert_failure "$?" "catalog validation rejects tap-formula packages without a slash"
assert_contains "$out" "invalid tap-formula package: missing-slash" "invalid tap-formula package is reported"

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

fake_dscl_bin="$TEST_TMP/fake-dscl-bin"
mkdir -p "$fake_dscl_bin"
cat >"$fake_dscl_bin/dscl" <<'EOF'
#!/bin/bash
printf 'UserShell: /opt/homebrew/bin/fish\n'
EOF
chmod +x "$fake_dscl_bin/dscl"
out="$TEST_TMP/doctor-unsupported-dscl-shell.out"
PATH="$fake_darwin_bin:$fake_dscl_bin:$PATH" SHELL=/bin/zsh run_capture "$out" ./rig doctor
assert_success "$?" "rig doctor succeeds with unsupported dscl login shell warning"
assert_contains "$out" "warning: unsupported login shell: fish" "doctor warning uses resolved login shell"
assert_not_contains "$out" "warning: unsupported login shell: zsh" "doctor warning does not fall back to SHELL when dscl resolved a shell"

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
assert_not_contains "$out" "Dry run: no files will be created or changed" "bootstrap dry-run does not render a plan on non-macOS"
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
