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
  if grep -F -- "$expected" "$file" >/dev/null 2>&1; then
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
  if grep -F -- "$unexpected" "$file" >/dev/null 2>&1; then
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
  -m)
    printf '%s\n' "${RIG_MACHINE_ARCH:-arm64}"
    ;;
  *)
    /usr/bin/uname "$@"
    ;;
esac
EOF
cat >"$fake_darwin_bin/sw_vers" <<'EOF'
#!/bin/bash
case "$1" in
  -productVersion)
    printf '%s\n' "${RIG_MACOS_VERSION:-15.0}"
    ;;
  *)
    if [ -x /usr/bin/sw_vers ]; then
      /usr/bin/sw_vers "$@"
    else
      printf '%s\n' "${RIG_MACOS_VERSION:-15.0}"
    fi
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
chmod +x "$fake_darwin_bin/uname" "$fake_darwin_bin/sw_vers" "$fake_linux_bin/uname"

fake_brew_bin="$TEST_TMP/fake-brew-bin"
fake_brew_log="$TEST_TMP/brew.log"
mkdir -p "$fake_brew_bin"
cat >"$fake_brew_bin/brew" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >>"$fake_brew_log"
case "\$1" in
  shellenv)
    printf 'export PATH=/fake/brew/bin:\$PATH\n'
    ;;
  update|upgrade)
    exit 0
    ;;
  tap|install)
    exit 0
    ;;
  autoupdate)
    exit 0
    ;;
esac
case "\$1:\$2" in
  bundle:install)
    exit 0
    ;;
esac
exit 0
EOF
chmod +x "$fake_brew_bin/brew"

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
  printf 'category\tid\tlabel\tkind\tpackage\tdefault\tdescription\tversion_strategy\tversions\tmin_macos\tarch\tnotes\n'
  printf 'ide\tvscode\tVisual Studio Code\tcask\tvisual-studio-code\tyes\tEditor\thomebrew-latest\t\t\t\t\n'
  printf 'browser\tvscode\tDuplicate\tcask\tduplicate\tno\tDuplicate id\thomebrew-latest\t\t\t\t\n'
} >"$duplicate_catalog"
out="$TEST_TMP/catalog-duplicate.out"
run_capture "$out" ./scripts/validate-catalog.sh --tools "$duplicate_catalog"
assert_failure "$?" "catalog validation rejects duplicate ids"
assert_contains "$out" "duplicate id: vscode" "duplicate id is reported"

missing_description="$TEST_TMP/missing-description.tsv"
{
  printf 'category\tid\tlabel\tkind\tpackage\tdefault\tdescription\tversion_strategy\tversions\tmin_macos\tarch\tnotes\n'
  printf 'ide\tvscode\tVisual Studio Code\tcask\tvisual-studio-code\tyes\t\thomebrew-latest\t\t\t\t\n'
} >"$missing_description"
out="$TEST_TMP/catalog-missing-description.out"
run_capture "$out" ./scripts/validate-catalog.sh --tools "$missing_description"
assert_failure "$?" "catalog validation rejects missing descriptions"
assert_contains "$out" "description is required" "missing description is reported"

interpolated_package_catalog="$TEST_TMP/interpolated-package-tools.tsv"
{
  printf 'category\tid\tlabel\tkind\tpackage\tdefault\tdescription\tversion_strategy\tversions\tmin_macos\tarch\tnotes\n'
  printf 'devops\tevil-brew\tEvil Brew\tformula\tevil#{system("touch /tmp/rig-pwned")}\tno\tBad package\thomebrew-latest\t\t\t\t\n'
} >"$interpolated_package_catalog"
out="$TEST_TMP/catalog-interpolated-package.out"
run_capture "$out" ./scripts/validate-catalog.sh --tools "$interpolated_package_catalog"
assert_failure "$?" "catalog validation rejects Ruby interpolation in Brewfile package fields"
assert_contains "$out" "invalid Brewfile package" "interpolated package is reported"

invalid_arch_catalog="$TEST_TMP/invalid-arch-tools.tsv"
{
  printf 'category\tid\tlabel\tkind\tpackage\tdefault\tdescription\tversion_strategy\tversions\tmin_macos\tarch\tnotes\n'
  printf 'ai\tbad-arch\tBad Arch\tcask\tbad-arch\tno\tBad arch\thomebrew-latest\t\t\tppc64\t\n'
} >"$invalid_arch_catalog"
out="$TEST_TMP/catalog-invalid-arch.out"
run_capture "$out" ./scripts/validate-catalog.sh --tools "$invalid_arch_catalog"
assert_failure "$?" "catalog validation rejects unsupported architecture tags"
assert_contains "$out" "invalid arch: ppc64" "invalid architecture tag is reported"

raw_defaults_catalog="$TEST_TMP/raw-command-defaults.tsv"
{
  printf 'id\tlabel\tdescription\tcommand\trestart_hint\n'
  printf 'evil-default\tEvil Default\tRuns shell\tdate > /tmp/rig-defaults-pwned\t\n'
} >"$raw_defaults_catalog"
out="$TEST_TMP/catalog-raw-defaults.out"
run_capture "$out" ./scripts/validate-catalog.sh --defaults "$raw_defaults_catalog"
assert_failure "$?" "catalog validation rejects raw macOS defaults command catalogs"
assert_contains "$out" "invalid macOS defaults catalog header" "raw defaults command schema is reported"

out="$TEST_TMP/version.out"
run_capture "$out" ./rig version
assert_success "$?" "rig version succeeds"
assert_contains "$out" "rig 0.1.0" "rig version reports MVP version"

out="$TEST_TMP/list-ai.out"
run_capture "$out" ./rig list --category ai
assert_success "$?" "rig list category succeeds"
assert_contains "$out" "codex-cli" "AI category includes Codex CLI"
assert_contains "$out" "chatgpt-desktop" "AI category includes ChatGPT Desktop"
assert_not_contains "$out" "google-chrome" "AI category excludes browser tools"

out="$TEST_TMP/list-ide.out"
run_capture "$out" ./rig list --category ide
assert_success "$?" "rig list IDE category succeeds"
assert_contains "$out" $'antigravity-ide\tAntigravity\t' "IDE category labels Antigravity consistently"
assert_contains "$out" "sublime-text" "IDE category includes Sublime Text"
assert_not_contains "$out" "Google Antigravity IDE" "IDE category avoids vendor-prefixed Antigravity label"

out="$TEST_TMP/list-communication.out"
run_capture "$out" ./rig list --category communication
assert_success "$?" "rig list communication category succeeds"
assert_contains "$out" "slack" "communication category includes Slack"
assert_contains "$out" "teams" "communication category includes Microsoft Teams"

out="$TEST_TMP/list-terminal.out"
run_capture "$out" ./rig list --category terminal
assert_success "$?" "rig list terminal category succeeds"
assert_contains "$out" "ghostty" "terminal category includes Ghostty"
assert_contains "$out" "warp" "terminal category includes Warp"

out="$TEST_TMP/list-unknown-category.out"
run_capture "$out" ./rig list --category does-not-exist
assert_failure "$?" "rig list rejects unknown categories"
assert_contains "$out" "unknown category: does-not-exist" "unknown list category is reported"

out="$TEST_TMP/dry-run.out"
PATH="$fake_darwin_bin:$PATH" run_capture "$out" ./rig dry-run --select vscode,chrome,node-npm --defaults finder-show-hidden-files
assert_success "$?" "rig dry-run succeeds"
assert_contains "$out" "# Summary" "dry-run prints summary section"
assert_contains "$out" "Homebrew-native packages: 2" "dry-run summary counts Homebrew-native packages"
assert_contains "$out" "External installers: 1" "dry-run summary counts external installers"
assert_contains "$out" "macOS defaults: 1" "dry-run summary counts macOS defaults"
assert_contains "$out" "Shell/profile edits: 1" "dry-run summary counts shell edits"
assert_contains "$out" "# Brewfile preview" "dry-run prints Brewfile section"
assert_contains "$out" "cask 'visual-studio-code'" "dry-run includes VS Code cask"
assert_contains "$out" "cask 'google-chrome'" "dry-run includes Chrome cask"
assert_not_contains "$out" '#{' "dry-run Brewfile preview does not expose Ruby interpolation"
assert_contains "$out" "# External install plan preview" "dry-run prints external plan section"
assert_contains "$out" "node-npm	nvm	latest	Node.js/npm" "dry-run includes Node external plan"
assert_contains "$out" "# macOS defaults preview" "dry-run prints macOS defaults section"
assert_contains "$out" "defaults write 'com.apple.finder' 'AppleShowAllFiles' -bool true" "dry-run includes selected Finder default"
assert_contains "$out" "# Shell/profile edits preview" "dry-run prints shell edits section"

out="$TEST_TMP/dry-run-expanded-catalog.out"
PATH="$fake_darwin_bin:$PATH" run_capture "$out" ./rig dry-run --select orbstack,docker-desktop,docker-cli,terraspace,awsume,zen,codex-desktop,chatgpt-desktop,claude-code-cli,claude-code-desktop,pi-cli,opencode-cli,opencode-desktop,antigravity-ide,kiro,sublime-text,ghostty,warp,slack,teams
assert_success "$?" "dry-run supports expanded catalog selections"
assert_contains "$out" "cask 'orbstack'" "dry-run includes OrbStack cask"
assert_contains "$out" "cask 'docker-desktop'" "dry-run includes Docker Desktop cask"
assert_contains "$out" "brew 'docker'" "dry-run includes Docker CLI formula"
assert_contains "$out" "tap 'boltops-tools/software'" "dry-run includes Terraspace tap"
assert_contains "$out" "brew 'terraspace'" "dry-run includes Terraspace formula"
assert_contains "$out" "brew 'awsume'" "dry-run includes awsume formula"
assert_contains "$out" "cask 'zen'" "dry-run includes Zen cask"
assert_contains "$out" "cask 'codex-app'" "dry-run includes Codex Desktop cask"
assert_contains "$out" "cask 'chatgpt'" "dry-run includes ChatGPT Desktop cask"
assert_contains "$out" "cask 'claude-code'" "dry-run includes Claude Code CLI cask"
assert_contains "$out" "cask 'claude'" "dry-run includes Claude Code Desktop app cask"
assert_contains "$out" "brew 'pi-coding-agent'" "dry-run includes Pi CLI formula"
assert_contains "$out" "brew 'opencode'" "dry-run includes OpenCode CLI formula"
assert_contains "$out" "cask 'opencode-desktop'" "dry-run includes OpenCode Desktop cask"
assert_contains "$out" "cask 'antigravity-ide'" "dry-run includes Antigravity cask"
assert_contains "$out" "cask 'kiro'" "dry-run includes Kiro cask"
assert_contains "$out" "cask 'sublime-text'" "dry-run includes Sublime Text cask"
assert_contains "$out" "cask 'ghostty'" "dry-run includes Ghostty cask"
assert_contains "$out" "cask 'warp'" "dry-run includes Warp cask"
assert_contains "$out" "cask 'slack'" "dry-run includes Slack cask"
assert_contains "$out" "cask 'microsoft-teams'" "dry-run includes Microsoft Teams cask"

out="$TEST_TMP/dry-run-min-macos.out"
PATH="$fake_darwin_bin:$PATH" RIG_MACOS_VERSION=13.6 run_capture "$out" ./rig dry-run --select orbstack
assert_failure "$?" "dry-run rejects tools above the current macOS version"
assert_contains "$out" "orbstack requires macOS 14 or newer; detected macOS 13.6" "unsupported macOS tool selection is reported"
assert_not_contains "$out" "cask 'orbstack'" "unsupported macOS tool selection does not render Brewfile"

out="$TEST_TMP/dry-run-chatgpt-min-macos.out"
PATH="$fake_darwin_bin:$PATH" RIG_MACOS_VERSION=13.6 run_capture "$out" ./rig dry-run --select chatgpt-desktop
assert_failure "$?" "dry-run rejects ChatGPT Desktop on unsupported macOS"
assert_contains "$out" "chatgpt-desktop requires macOS 14 or newer; detected macOS 13.6" "ChatGPT Desktop reports unsupported macOS"
assert_not_contains "$out" "cask 'chatgpt'" "ChatGPT Desktop unsupported macOS selection does not render Brewfile"

out="$TEST_TMP/dry-run-chatgpt-arch.out"
PATH="$fake_darwin_bin:$PATH" RIG_MACHINE_ARCH=x86_64 run_capture "$out" ./rig dry-run --select chatgpt-desktop
assert_failure "$?" "dry-run rejects ChatGPT Desktop on unsupported architecture"
assert_contains "$out" "chatgpt-desktop requires arm64; detected x86_64" "ChatGPT Desktop reports unsupported architecture"
assert_not_contains "$out" "cask 'chatgpt'" "ChatGPT Desktop unsupported architecture selection does not render Brewfile"

out="$TEST_TMP/install-write-config-min-macos.out"
old_macos_home="$TEST_TMP/install-write-config-min-macos-home"
mkdir -p "$old_macos_home"
PATH="$fake_darwin_bin:$PATH" RIG_MACOS_VERSION=13.6 HOME="$old_macos_home" RIG_CONFIG_DIR="$old_macos_home/.config/rig" run_capture "$out" ./rig install --write-config-only --select docker-desktop
assert_failure "$?" "write-config-only rejects tools above the current macOS version"
assert_contains "$out" "docker-desktop requires macOS 14 or newer; detected macOS 13.6" "write-config-only reports unsupported macOS tool selection"
if [ -e "$old_macos_home/.config/rig" ]; then
  fail "write-config-only unsupported macOS selection does not write config"
else
  pass "write-config-only unsupported macOS selection does not write config"
fi

out="$TEST_TMP/install-write-config-chatgpt-arch.out"
unsupported_arch_home="$TEST_TMP/install-write-config-chatgpt-arch-home"
mkdir -p "$unsupported_arch_home"
PATH="$fake_darwin_bin:$PATH" RIG_MACHINE_ARCH=x86_64 HOME="$unsupported_arch_home" RIG_CONFIG_DIR="$unsupported_arch_home/.config/rig" run_capture "$out" ./rig install --write-config-only --select chatgpt-desktop
assert_failure "$?" "write-config-only rejects ChatGPT Desktop on unsupported architecture"
assert_contains "$out" "chatgpt-desktop requires arm64; detected x86_64" "write-config-only reports unsupported ChatGPT Desktop architecture"
if [ -e "$unsupported_arch_home/.config/rig" ]; then
  fail "write-config-only unsupported architecture selection does not write config"
else
  pass "write-config-only unsupported architecture selection does not write config"
fi

tap_tools_catalog="$TEST_TMP/tap-tools.tsv"
{
  printf 'category\tid\tlabel\tkind\tpackage\tdefault\tdescription\tversion_strategy\tversions\tmin_macos\tarch\tnotes\n'
  printf 'devops\ttap-tool\tTap Tool\ttap-formula\towner/tap/tool\tno\tTool from a tap\thomebrew-latest\t\t\t\t\n'
} >"$tap_tools_catalog"
out="$TEST_TMP/dry-run-tap-formula-summary.out"
PATH="$fake_darwin_bin:$PATH" RIG_TOOLS_CATALOG="$tap_tools_catalog" run_capture "$out" ./rig dry-run --select tap-tool
assert_success "$?" "rig dry-run succeeds with tap-formula tool"
assert_contains "$out" "tap 'owner/tap'" "dry-run includes tap for tap-formula tool"
assert_contains "$out" "brew 'tool'" "dry-run includes formula for tap-formula tool"
assert_contains "$out" "Homebrew-native packages: 1" "dry-run summary counts tap-formula as one package"

out="$TEST_TMP/dry-run-non-macos.out"
PATH="$fake_linux_bin:$PATH" RIG_LOGIN_SHELL=/bin/zsh run_capture "$out" ./rig dry-run --select vscode
assert_failure "$?" "rig dry-run fails clearly on non-macOS"
assert_contains "$out" "rig supports macOS only; detected Linux" "dry-run reports macOS-only guard"
assert_not_contains "$out" "cask 'visual-studio-code'" "dry-run does not render a plan on non-macOS"

out="$TEST_TMP/dry-run-repeated-select.out"
PATH="$fake_darwin_bin:$PATH" run_capture "$out" ./rig dry-run --select vscode --select chrome
assert_failure "$?" "dry-run rejects repeated --select"
assert_contains "$out" "repeated --select is not supported" "repeated --select is reported"

out="$TEST_TMP/dry-run-repeated-defaults.out"
PATH="$fake_darwin_bin:$PATH" run_capture "$out" ./rig dry-run --defaults finder-show-hidden-files --defaults dock-autohide
assert_failure "$?" "dry-run rejects repeated --defaults"
assert_contains "$out" "repeated --defaults is not supported" "repeated --defaults is reported"

out="$TEST_TMP/dry-run-unknown-default.out"
PATH="$fake_darwin_bin:$PATH" run_capture "$out" ./rig dry-run --defaults does-not-exist
assert_failure "$?" "dry-run rejects unknown defaults"
assert_contains "$out" "unknown macOS default id: does-not-exist" "unknown default id is reported"

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
assert_contains "$out" "cask 'visual-studio-code'" "install --dry-run delegates to dry-run"

out="$TEST_TMP/install-dry-run-non-tty.out"
non_tty_home="$TEST_TMP/install-dry-run-non-tty-home"
mkdir -p "$non_tty_home"
PATH="$fake_darwin_bin:/usr/bin:/bin" HOME="$non_tty_home" RIG_CONFIG_DIR="$non_tty_home/.config/rig" RIG_LOGIN_SHELL=/bin/zsh run_capture "$out" ./rig install --dry-run
assert_failure "$?" "rig install --dry-run without selections requires a terminal"
assert_contains "$out" "interactive selection requires a terminal" "non-tty interactive dry-run reports terminal requirement"
assert_not_contains "$out" "Category: browser" "non-tty interactive dry-run does not spill categories"

missing_brew_prefix="$TEST_TMP/missing-brew-prefix"
homebrew_install_command="/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
out="$TEST_TMP/install-dry-run-missing-homebrew.out"
dry_run_home="$TEST_TMP/dry-run-missing-homebrew-home"
mkdir -p "$dry_run_home"
PATH="$fake_darwin_bin:/usr/bin:/bin" HOME="$dry_run_home" RIG_CONFIG_DIR="$dry_run_home/.config/rig" RIG_HOMEBREW_PREFIX="$missing_brew_prefix" RIG_LOGIN_SHELL=/bin/zsh run_capture "$out" ./rig install --dry-run --select gh
assert_success "$?" "rig install --dry-run previews missing Homebrew"
assert_contains "$out" "# Homebrew prerequisite preview" "install --dry-run prints Homebrew prerequisite section"
assert_contains "$out" "Would ask for approval to install Homebrew" "install --dry-run explains Homebrew approval"
assert_contains "$out" "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" "install --dry-run discloses Homebrew installer URL"
assert_contains "$out" "$homebrew_install_command" "install --dry-run discloses Homebrew install command"
if [ -e "$dry_run_home/.config/rig" ]; then
  fail "rig install --dry-run missing Homebrew does not write config"
else
  pass "rig install --dry-run missing Homebrew does not write config"
fi

out="$TEST_TMP/install-dry-run-missing-homebrew-interactive.out"
interactive_dry_run_home="$TEST_TMP/interactive-dry-run-missing-homebrew-home"
mkdir -p "$interactive_dry_run_home"
# shellcheck disable=SC2016
PATH="$fake_darwin_bin:/usr/bin:/bin" HOME="$interactive_dry_run_home" RIG_CONFIG_DIR="$interactive_dry_run_home/.config/rig" RIG_HOMEBREW_PREFIX="$missing_brew_prefix" RIG_LOGIN_SHELL=/bin/zsh run_capture "$out" bash -c '
  {
    printf "y\n"
    category_count=$(awk -F "\t" "NR>1 && !seen[\$1]++ { count++ } END { print count }" "'"$ROOT_DIR"'/catalog/tools.tsv")
    i=0
    while [ "$i" -lt "$category_count" ]; do
      printf "\n"
      i=$((i + 1))
    done
    printf "\n"
    printf "\n"
    printf "\n"
  } | RIG_ALLOW_NON_TTY_PROMPTS=yes ./rig install --dry-run
'
assert_success "$?" "rig install --dry-run can simulate approving missing Homebrew"
assert_contains "$out" "Would install Homebrew before showing tool selections" "interactive dry-run reports simulated Homebrew install"
assert_contains "$out" "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" "interactive install --dry-run discloses Homebrew installer URL"
assert_contains "$out" "$homebrew_install_command" "interactive install --dry-run discloses Homebrew install command"
assert_contains "$out" "IDEs and editors" "interactive dry-run reaches tool selection after approval"
assert_not_contains "$out" "Selection: Enable automatic" "interactive dry-run keeps prompts on separate lines"
if [ -e "$interactive_dry_run_home/.config/rig" ]; then
  fail "interactive rig install --dry-run does not write config"
else
  pass "interactive rig install --dry-run does not write config"
fi

out="$TEST_TMP/install-dry-run-all-categories.out"
all_categories_home="$TEST_TMP/install-dry-run-all-categories-home"
mkdir -p "$all_categories_home"
# shellcheck disable=SC2016
PATH="$fake_darwin_bin:$fake_brew_bin:/usr/bin:/bin" HOME="$all_categories_home" RIG_CONFIG_DIR="$all_categories_home/.config/rig" RIG_LOGIN_SHELL=/bin/zsh run_capture "$out" bash -c '
  category_count=$(awk -F "\t" "NR>1 && !seen[\$1]++ { count++ } END { print count }" "'"$ROOT_DIR"'/catalog/tools.tsv")
  {
    i=0
    while [ "$i" -lt "$category_count" ]; do
      printf "\n"
      i=$((i + 1))
    done
    printf "\n"
    printf "\n"
    printf "\n"
  } | RIG_ALLOW_NON_TTY_PROMPTS=yes RIG_PROMPT_NO_CLEAR=yes ./rig install --dry-run
'
assert_success "$?" "interactive dry-run blank selection traverses all categories"
assert_contains "$out" "AI tools" "interactive dry-run includes AI category"
assert_contains "$out" "JavaScript runtimes" "interactive dry-run includes runtime category"
assert_contains "$out" "Infrastructure tools" "interactive dry-run includes infra category"
assert_contains "$out" "Productivity and security" "interactive dry-run includes productivity category"
assert_contains "$out" "Review selection" "interactive dry-run shows final review"

out="$TEST_TMP/install-missing-homebrew-decline.out"
decline_brew_home="$TEST_TMP/install-missing-homebrew-decline-home"
mkdir -p "$decline_brew_home"
PATH="$fake_darwin_bin:/usr/bin:/bin" HOME="$decline_brew_home" RIG_CONFIG_DIR="$decline_brew_home/.config/rig" RIG_HOMEBREW_PREFIX="$missing_brew_prefix" RIG_LOGIN_SHELL=/bin/zsh run_capture "$out" bash -c 'printf "n\n" | RIG_ALLOW_NON_TTY_PROMPTS=yes ./rig install'
assert_failure "$?" "rig install exits when interactive user declines Homebrew"
assert_contains "$out" "Install Homebrew now?" "interactive missing Homebrew asks for approval"
assert_not_contains "$out" "Category:" "interactive decline exits before tool selection"
if [ -e "$decline_brew_home/.config/rig" ]; then
  fail "rig install decline missing Homebrew does not write config"
else
  pass "rig install decline missing Homebrew does not write config"
fi

out="$TEST_TMP/install-missing-homebrew-no-yes.out"
missing_brew_home="$TEST_TMP/install-missing-homebrew-home"
mkdir -p "$missing_brew_home"
PATH="$fake_darwin_bin:/usr/bin:/bin" HOME="$missing_brew_home" RIG_CONFIG_DIR="$missing_brew_home/.config/rig" RIG_HOMEBREW_PREFIX="$missing_brew_prefix" RIG_LOGIN_SHELL=/bin/zsh run_capture "$out" ./rig install --select gh
assert_failure "$?" "rig install --select requires --yes when Homebrew is missing"
assert_contains "$out" "Homebrew is required to install selected software" "missing Homebrew is reported"
assert_contains "$out" "--yes" "missing Homebrew non-interactive error mentions --yes"
if [ -e "$missing_brew_home/.config/rig" ]; then
  fail "rig install missing Homebrew without --yes does not write config"
else
  pass "rig install missing Homebrew without --yes does not write config"
fi

fake_curl_bin="$TEST_TMP/fake-curl-bin"
mkdir -p "$fake_curl_bin"
cat >"$fake_curl_bin/curl" <<'EOF'
#!/bin/bash
cat <<'INSTALLER'
#!/bin/bash
mkdir -p "$RIG_HOMEBREW_PREFIX/bin"
cat >"$RIG_HOMEBREW_PREFIX/bin/brew" <<'BREW'
#!/bin/bash
case "$1" in
  shellenv)
    printf 'export PATH=%s/bin:$PATH\n' "$RIG_HOMEBREW_PREFIX"
    ;;
esac
case "$1:$2" in
  bundle:install)
    exit 0
    ;;
esac
exit 0
BREW
chmod +x "$RIG_HOMEBREW_PREFIX/bin/brew"
INSTALLER
EOF
chmod +x "$fake_curl_bin/curl"
out="$TEST_TMP/install-missing-homebrew-yes.out"
approved_brew_home="$TEST_TMP/install-missing-homebrew-yes-home"
approved_brew_prefix="$TEST_TMP/approved-brew-prefix"
mkdir -p "$approved_brew_home"
PATH="$fake_darwin_bin:$fake_curl_bin:/usr/bin:/bin" HOME="$approved_brew_home" RIG_CONFIG_DIR="$approved_brew_home/.config/rig" RIG_HOMEBREW_PREFIX="$approved_brew_prefix" RIG_LOGIN_SHELL=/bin/zsh run_capture "$out" ./rig install --yes --select gh
assert_success "$?" "rig install --yes installs missing Homebrew before selected tools"
assert_contains "$out" "Installing Homebrew" "--yes path reports Homebrew installation"
assert_success "$([ -x "$approved_brew_prefix/bin/brew" ] && echo 0 || echo 1)" "--yes path creates Homebrew through installer"
assert_success "$([ -f "$approved_brew_home/.config/rig/Brewfile" ] && echo 0 || echo 1)" "--yes path writes config after Homebrew preflight"

out="$TEST_TMP/install-interactive-empty.out"
interactive_home="$TEST_TMP/interactive-home"
mkdir -p "$interactive_home"
# shellcheck disable=SC2016
PATH="$fake_darwin_bin:$fake_brew_bin:/usr/bin:/bin" HOME="$interactive_home" RIG_CONFIG_DIR="$interactive_home/.config/rig" run_capture "$out" bash -c '
  category_count=$(awk -F "\t" "NR>1 && !seen[\$1]++ { count++ } END { print count }" "'"$ROOT_DIR"'/catalog/tools.tsv")
  {
    i=0
    while [ "$i" -lt "$category_count" ]; do
      printf "\n"
      i=$((i + 1))
    done
    printf "\n"
    printf "\n"
    printf "y\n"
  } | RIG_ALLOW_NON_TTY_PROMPTS=yes ./rig install
'
assert_success "$?" "rig install interactive default path succeeds with no selections"
assert_contains "$out" "Wrote rig config" "interactive install writes config"
assert_contains "$out" "Review selection" "interactive install shows final review"
assert_success "$([ -f "$interactive_home/.config/rig/Brewfile" ] && echo 0 || echo 1)" "interactive install creates Brewfile"

out="$TEST_TMP/install-dry-run-non-macos.out"
PATH="$fake_linux_bin:$PATH" RIG_LOGIN_SHELL=/bin/zsh run_capture "$out" ./rig install --dry-run --select vscode
assert_failure "$?" "rig install --dry-run fails clearly on non-macOS"
assert_contains "$out" "rig supports macOS only; detected Linux" "install --dry-run reports macOS-only guard"
assert_not_contains "$out" "cask 'visual-studio-code'" "install --dry-run does not render a plan on non-macOS"

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
  *"cask 'visual-studio-code'"*) pass "Brewfile contains VS Code" ;;
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

defaults_only_home="$TEST_TMP/defaults-only-home"
mkdir -p "$defaults_only_home/.config/rig"
: >"$defaults_only_home/.config/rig/macos-defaults.sh"
out="$TEST_TMP/install-from-config-defaults-only.out"
PATH="$fake_darwin_bin:/usr/bin:/bin" HOME="$defaults_only_home" RIG_CONFIG_DIR="$defaults_only_home/.config/rig" RIG_HOMEBREW_PREFIX="$TEST_TMP/missing-brew-prefix" RIG_SKIP_HOMEBREW_INSTALL=yes run_capture "$out" ./rig install --from-config
assert_success "$?" "rig install --from-config defaults-only succeeds without Homebrew"
assert_not_contains "$out" "Homebrew is required" "defaults-only from-config replay does not require Homebrew"

rm -f "$fake_brew_log"
apply_home="$TEST_TMP/apply-home"
mkdir -p "$apply_home/.config/rig"
printf 'cask "visual-studio-code"\n' >"$apply_home/.config/rig/Brewfile"
printf 'id\tstrategy\tpackage\tversion\tlabel\n' >"$apply_home/.config/rig/install-plan.tsv"
printf '#!/bin/bash\n' >"$apply_home/.config/rig/macos-defaults.sh"
PATH="$fake_darwin_bin:$fake_brew_bin:$PATH" HOME="$apply_home" RIG_CONFIG_DIR="$apply_home/.config/rig" RIG_SKIP_HOMEBREW_INSTALL=yes run_capture "$out" ./rig install --from-config
assert_success "$?" "rig install --from-config succeeds with mock brew"
assert_contains "$fake_brew_log" "bundle install --file=" "from-config invokes brew bundle"

tampered_defaults_home="$TEST_TMP/tampered-defaults-home"
tampered_defaults_marker="$TEST_TMP/tampered-defaults-marker"
mkdir -p "$tampered_defaults_home/.config/rig"
: >"$tampered_defaults_home/.config/rig/Brewfile"
printf 'id\tstrategy\tpackage\tversion\tlabel\n' >"$tampered_defaults_home/.config/rig/install-plan.tsv"
{
  printf '#!/bin/bash\n'
  printf 'touch "%s"\n' "$tampered_defaults_marker"
} >"$tampered_defaults_home/.config/rig/macos-defaults.sh"
out="$TEST_TMP/install-from-config-tampered-defaults.out"
PATH="$fake_darwin_bin:$fake_brew_bin:$PATH" HOME="$tampered_defaults_home" RIG_CONFIG_DIR="$tampered_defaults_home/.config/rig" RIG_SKIP_HOMEBREW_INSTALL=yes run_capture "$out" ./rig install --from-config
assert_failure "$?" "rig install --from-config rejects tampered macOS defaults scripts"
assert_contains "$out" "unsupported macOS defaults command" "tampered defaults script is reported"
if [ -e "$tampered_defaults_marker" ]; then
  fail "tampered macOS defaults script is not executed"
else
  pass "tampered macOS defaults script is not executed"
fi

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

out="$TEST_TMP/install-help-non-macos.out"
PATH="$fake_linux_bin:$PATH" run_capture "$out" ./rig install --select vscode --help
assert_success "$?" "rig install --help works before macOS guard"
assert_contains "$out" "Usage: rig install" "install help is shown on non-macOS"
assert_not_contains "$out" "rig supports macOS only" "install help does not enforce macOS"

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
assert_contains "$out" "[--yes]" "install help includes yes flag"

out="$TEST_TMP/rig-usage-install-constant.out"
RIG_ROOT="$ROOT_DIR" bash -c '
  . "'"$ROOT_DIR"'/lib/rig/common.sh"
  RIG_INSTALL_USAGE="Usage: rig install --sentinel"
  rig_usage
' >"$out" 2>&1
assert_success "$?" "rig usage renders with overridden install usage"
assert_contains "$out" "rig install --sentinel" "rig usage reuses install usage constant"

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

out="$TEST_TMP/tenv-only-homebrew-required.out"
RIG_ROOT="$ROOT_DIR" bash -c '
  . "'"$ROOT_DIR"'/lib/rig/common.sh"
  . "'"$ROOT_DIR"'/lib/rig/brew.sh"
  . "'"$ROOT_DIR"'/lib/rig/apply.sh"
  rig_command_exists() { return 1; }
  rig_brew_shellenv() {
    rig_print_error "direct brew shellenv path"
    return 1
  }
  rig_ensure_homebrew() {
    rig_print_error "Homebrew is required but RIG_SKIP_HOMEBREW_INSTALL=yes"
    return 1
  }
  rig_apply_tenv tenv:tf latest
' >"$out" 2>&1
assert_failure "$?" "tenv-only install requires Homebrew before apply"
assert_contains "$out" "Homebrew is required but RIG_SKIP_HOMEBREW_INSTALL=yes" "tenv-only install uses Homebrew ensure path"
assert_not_contains "$out" "direct brew shellenv path" "tenv-only install avoids direct shellenv path"

id_prefixed_plan="$TEST_TMP/id-prefixed-install-plan.tsv"
printf 'id\tstrategy\tpackage\tversion\tlabel\n' >"$id_prefixed_plan"
printf 'id-local\tnvm\tnvm\tlatest\tId Local\n' >>"$id_prefixed_plan"
out="$TEST_TMP/id-prefixed-install-plan-apply.out"
RIG_ROOT="$ROOT_DIR" bash -c '
  . "'"$ROOT_DIR"'/lib/rig/common.sh"
  . "'"$ROOT_DIR"'/lib/rig/catalog.sh"
  . "'"$ROOT_DIR"'/lib/rig/apply.sh"
  rig_apply_install_plan "'"$id_prefixed_plan"'"
' >"$out" 2>&1
assert_failure "$?" "install-plan apply does not skip id-prefixed rows as headers"
assert_contains "$out" "unknown catalog id: id-local" "id-prefixed apply row is validated"

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
  rig_prompt_review_selection() { return 0; }
  rig_validate_catalogs
  RIG_ALLOW_NON_TTY_PROMPTS=yes
  rig_run_interactive_selection
  printf "tools:%s" "$RIG_PLAN_SELECTED_TOOLS"
' >"$out" 2>&1
assert_success "$?" "interactive selection stub succeeds"
assert_contains "$out" "tools:vscode" "interactive selection stub selects vscode"

out="$TEST_TMP/interactive-selection-auto-update-flag.out"
PATH="$fake_darwin_bin:$PATH" RIG_ROOT="$ROOT_DIR" bash -c '
  . "'"$ROOT_DIR"'/lib/rig/common.sh"
  . "'"$ROOT_DIR"'/lib/rig/catalog.sh"
  . "'"$ROOT_DIR"'/lib/rig/plan.sh"
  . "'"$ROOT_DIR"'/lib/rig/prompts.sh"
  rig_each_category() { return 0; }
  rig_prompt_defaults() { return 0; }
  rig_prompt_auto_update() {
    printf "auto-update prompt was called\n" >&2
    printf "no\n"
  }
  rig_prompt_review_selection() {
    printf "auto:%s\n" "$RIG_PLAN_AUTO_UPDATE"
    return 0
  }
  RIG_ALLOW_NON_TTY_PROMPTS=yes
  RIG_PLAN_AUTO_UPDATE=yes
  rig_run_interactive_selection
' >"$out" 2>&1
assert_success "$?" "interactive selection honors --auto-update flag"
assert_contains "$out" "auto:yes" "interactive selection preserves CLI auto-update choice"
assert_not_contains "$out" "auto-update prompt was called" "interactive selection skips auto-update prompt when flag is set"

out="$TEST_TMP/prompt-yes-no-eof.out"
PATH="$fake_darwin_bin:$PATH" RIG_ROOT="$ROOT_DIR" bash -c '
  . "'"$ROOT_DIR"'/lib/rig/common.sh"
  . "'"$ROOT_DIR"'/lib/rig/prompts.sh"
  rig_prompt_yes_no "Proceed?" yes < /dev/null
' >"$out" 2>&1
assert_failure "$?" "yes/no prompt fails closed on EOF"
assert_contains "$out" "Proceed? [Y/n]:" "yes/no prompt renders default before EOF"

prompt_stderr="$TEST_TMP/prompt-sanitized-rows.stderr"
PATH="$fake_darwin_bin:$PATH" RIG_ROOT="$ROOT_DIR" bash -c '
  . "'"$ROOT_DIR"'/lib/rig/common.sh"
  . "'"$ROOT_DIR"'/lib/rig/prompts.sh"
  esc=$(printf "\033")
  items=$(printf "evil|Bad%s[2JLabel|Desc%s[31m\n" "$esc" "$esc")
  rig_prompt_render_multi_select_rows "$items" "" 1 tools
' >"$TEST_TMP/prompt-sanitized-rows.stdout" 2>"$prompt_stderr"
assert_success "$?" "prompt row rendering succeeds with control characters"
assert_contains "$prompt_stderr" "Bad[2JLabel" "prompt row keeps printable text from escaped label"
assert_not_contains "$prompt_stderr" "$(printf '\033')" "prompt row strips terminal escape bytes"

prompt_stderr="$TEST_TMP/prompt-sanitized-review.stderr"
PATH="$fake_darwin_bin:$PATH" RIG_ROOT="$ROOT_DIR" bash -c '
  . "'"$ROOT_DIR"'/lib/rig/common.sh"
  . "'"$ROOT_DIR"'/lib/rig/catalog.sh"
  . "'"$ROOT_DIR"'/lib/rig/prompts.sh"
  esc=$(printf "\033")
  rig_each_category() { printf "ide\n"; }
  rig_lookup_tool() {
    d=$RIG_TSV_DELIMITER
    printf "ide%sevil%sBad%s[2JTool%scask%sevil%sno%sDesc%shomebrew-latest%s%s\n" "$d" "$d" "$esc" "$d" "$d" "$d" "$d" "$d" "$d" "$d"
  }
  rig_lookup_default() {
    d=$RIG_TSV_DELIMITER
    printf "evil-default%sBad%s[2JDefault%sDesc%scom.example%sKey%sbool%strue%s\n" "$d" "$esc" "$d" "$d" "$d" "$d" "$d" "$d"
  }
  rig_prompt_print_review_tools "$(printf "evil\n")"
  rig_prompt_print_review_defaults "$(printf "evil-default\n")"
' >"$TEST_TMP/prompt-sanitized-review.stdout" 2>"$prompt_stderr"
assert_success "$?" "review rendering succeeds with control characters"
assert_contains "$prompt_stderr" "Bad[2JTool" "review rendering keeps printable text from escaped tool label"
assert_contains "$prompt_stderr" "Bad[2JDefault" "review rendering keeps printable text from escaped default label"
assert_not_contains "$prompt_stderr" "$(printf '\033')" "review rendering strips terminal escape bytes"

prompt_stdout="$TEST_TMP/review-selection.stdout"
prompt_stderr="$TEST_TMP/review-selection.stderr"
PATH="$fake_darwin_bin:/usr/bin:/bin" RIG_ROOT="$ROOT_DIR" bash -c '
  . "'"$ROOT_DIR"'/lib/rig/common.sh"
  . "'"$ROOT_DIR"'/lib/rig/catalog.sh"
  . "'"$ROOT_DIR"'/lib/rig/prompts.sh"
  rig_validate_catalogs
  RIG_PLAN_SELECTED_TOOLS=$(printf "vscode\nfirefox\nnode-npm\n")
  RIG_PLAN_SELECTED_DEFAULTS=$(printf "finder-show-hidden-files\n")
  RIG_PLAN_AUTO_UPDATE=yes
  RIG_PLAN_DRY_RUN=no
  printf "y\n" | rig_prompt_review_selection
' >"$prompt_stdout" 2>"$prompt_stderr"
assert_success "$?" "review prompt accepts confirmation"
if [ ! -s "$prompt_stdout" ]; then
  pass "review prompt keeps stdout empty"
else
  printf '%s\n' "---- stdout ----"
  cat "$prompt_stdout"
  printf '%s\n' "----------------"
  fail "review prompt keeps stdout empty"
fi
assert_contains "$prompt_stderr" "Review selection" "review prompt prints heading"
assert_contains "$prompt_stderr" "IDEs and editors: Visual Studio Code" "review prompt groups IDE tools"
assert_contains "$prompt_stderr" "Browsers: Firefox" "review prompt groups browser tools"
assert_contains "$prompt_stderr" "JavaScript runtimes: Node.js/npm" "review prompt groups runtime tools"
assert_contains "$prompt_stderr" "macOS preferences" "review prompt prints defaults section"
assert_contains "$prompt_stderr" "Show hidden files" "review prompt shows selected default labels"
assert_contains "$prompt_stderr" "Homebrew auto-update: yes" "review prompt shows auto-update selection"
assert_contains "$prompt_stderr" "Continue with install?" "review prompt asks before install"

prompt_stdout="$TEST_TMP/prompt-tools.stdout"
prompt_stderr="$TEST_TMP/prompt-tools.stderr"
PATH="$fake_darwin_bin:/usr/bin:/bin" RIG_ROOT="$ROOT_DIR" bash -c '
  . "'"$ROOT_DIR"'/lib/rig/common.sh"
  . "'"$ROOT_DIR"'/lib/rig/catalog.sh"
  . "'"$ROOT_DIR"'/lib/rig/prompts.sh"
  rig_validate_catalogs
  RIG_PROMPT_STEP=1
  RIG_PROMPT_TOTAL=9
  printf "\n" | rig_prompt_tools_for_category ide
' >"$prompt_stdout" 2>"$prompt_stderr"
assert_success "$?" "plain tool prompt succeeds with blank selection"
if [ ! -s "$prompt_stdout" ]; then
  pass "plain tool prompt keeps stdout selection-only"
else
  printf '%s\n' "---- stdout ----"
  cat "$prompt_stdout"
  printf '%s\n' "----------------"
  fail "plain tool prompt keeps stdout selection-only"
fi
assert_contains "$prompt_stderr" "rig setup | 1/9 IDEs and editors | selected 0" "plain tool prompt writes progress header to stderr"
assert_contains "$prompt_stderr" "IDEs and editors" "plain tool prompt writes category heading to stderr"
assert_contains "$prompt_stderr" "> [ ] Visual Studio Code" "plain tool prompt renders active checkbox row without numbers"
assert_contains "$prompt_stderr" "vscode" "plain tool prompt shows catalog id"
assert_contains "$prompt_stderr" "Up/Down move  Space toggle  Enter continue" "plain tool prompt explains compact keyboard footer"
assert_not_contains "$prompt_stderr" "> [ ] 1  Visual Studio Code" "plain tool prompt hides numeric choices"
assert_not_contains "$prompt_stderr" "Category: ide" "plain tool prompt does not use raw category dump"

prompt_stdout="$TEST_TMP/prompt-tools-space.stdout"
prompt_stderr="$TEST_TMP/prompt-tools-space.stderr"
PATH="$fake_darwin_bin:/usr/bin:/bin" RIG_ROOT="$ROOT_DIR" bash -c '
  . "'"$ROOT_DIR"'/lib/rig/common.sh"
  . "'"$ROOT_DIR"'/lib/rig/catalog.sh"
  . "'"$ROOT_DIR"'/lib/rig/prompts.sh"
  rig_validate_catalogs
  printf " \n" | rig_prompt_tools_for_category ide
' >"$prompt_stdout" 2>"$prompt_stderr"
assert_success "$?" "plain tool prompt selects current row with space"
prompt_value=$(cat "$prompt_stdout")
if [ "$prompt_value" = "vscode" ]; then
  pass "plain tool prompt emits selected current row id"
else
  printf '%s\n' "---- stdout ----"
  cat "$prompt_stdout"
  printf '%s\n' "----------------"
  fail "plain tool prompt emits selected current row id"
fi

prompt_stdout="$TEST_TMP/prompt-tools-arrow.stdout"
prompt_stderr="$TEST_TMP/prompt-tools-arrow.stderr"
PATH="$fake_darwin_bin:/usr/bin:/bin" RIG_ROOT="$ROOT_DIR" bash -c '
  . "'"$ROOT_DIR"'/lib/rig/common.sh"
  . "'"$ROOT_DIR"'/lib/rig/catalog.sh"
  . "'"$ROOT_DIR"'/lib/rig/prompts.sh"
  rig_validate_catalogs
  printf "\033[B \n" | rig_prompt_tools_for_category browser
' >"$prompt_stdout" 2>"$prompt_stderr"
assert_success "$?" "plain tool prompt moves with down arrow"
assert_contains "$prompt_stderr" "selected 1" "plain tool prompt updates selected count after toggling"
prompt_value=$(cat "$prompt_stdout")
if [ "$prompt_value" = "firefox" ]; then
  pass "plain tool prompt emits arrow-selected row id"
else
  printf '%s\n' "---- stdout ----"
  cat "$prompt_stdout"
  printf '%s\n' "----------------"
  fail "plain tool prompt emits arrow-selected row id"
fi

prompt_stdout="$TEST_TMP/prompt-version.stdout"
prompt_stderr="$TEST_TMP/prompt-version.stderr"
PATH="$fake_darwin_bin:/usr/bin:/bin" RIG_ROOT="$ROOT_DIR" bash -c '
  . "'"$ROOT_DIR"'/lib/rig/common.sh"
  . "'"$ROOT_DIR"'/lib/rig/catalog.sh"
  . "'"$ROOT_DIR"'/lib/rig/prompts.sh"
  rig_validate_catalogs
  printf "lts\n" | rig_prompt_version node-npm latest,lts
' >"$prompt_stdout" 2>"$prompt_stderr"
assert_success "$?" "plain version prompt succeeds"
prompt_value=$(cat "$prompt_stdout")
if [ "$prompt_value" = "lts" ]; then
  pass "plain version prompt keeps stdout to selected version"
else
  printf '%s\n' "---- stdout ----"
  cat "$prompt_stdout"
  printf '%s\n' "----------------"
  fail "plain version prompt keeps stdout to selected version"
fi
assert_contains "$prompt_stderr" "Version [latest]" "plain version prompt writes prompt to stderr"

prompt_stdout="$TEST_TMP/prompt-defaults.stdout"
prompt_stderr="$TEST_TMP/prompt-defaults.stderr"
PATH="$fake_darwin_bin:/usr/bin:/bin" RIG_ROOT="$ROOT_DIR" bash -c '
  . "'"$ROOT_DIR"'/lib/rig/common.sh"
  . "'"$ROOT_DIR"'/lib/rig/catalog.sh"
  . "'"$ROOT_DIR"'/lib/rig/prompts.sh"
  rig_validate_catalogs
  printf "\n" | rig_prompt_defaults
' >"$prompt_stdout" 2>"$prompt_stderr"
assert_success "$?" "plain defaults prompt succeeds with blank selection"
if [ ! -s "$prompt_stdout" ]; then
  pass "plain defaults prompt keeps stdout selection-only"
else
  printf '%s\n' "---- stdout ----"
  cat "$prompt_stdout"
  printf '%s\n' "----------------"
  fail "plain defaults prompt keeps stdout selection-only"
fi
assert_contains "$prompt_stderr" "macOS preferences" "plain defaults prompt writes heading to stderr"
assert_contains "$prompt_stderr" "> [ ] Show hidden files" "plain defaults prompt renders active checkbox row with label"
assert_contains "$prompt_stderr" "finder-show-hidden-files" "plain defaults prompt shows default id"
assert_contains "$prompt_stderr" "Show hidden files in Finder" "plain defaults prompt includes default descriptions"

prompt_stdout="$TEST_TMP/prompt-defaults-space.stdout"
prompt_stderr="$TEST_TMP/prompt-defaults-space.stderr"
PATH="$fake_darwin_bin:/usr/bin:/bin" RIG_ROOT="$ROOT_DIR" bash -c '
  . "'"$ROOT_DIR"'/lib/rig/common.sh"
  . "'"$ROOT_DIR"'/lib/rig/catalog.sh"
  . "'"$ROOT_DIR"'/lib/rig/prompts.sh"
  rig_validate_catalogs
  printf " \n" | rig_prompt_defaults
' >"$prompt_stdout" 2>"$prompt_stderr"
assert_success "$?" "plain defaults prompt selects current row with space"
prompt_value=$(cat "$prompt_stdout")
if [ "$prompt_value" = "finder-show-hidden-files" ]; then
  pass "plain defaults prompt emits selected row id"
else
  printf '%s\n' "---- stdout ----"
  cat "$prompt_stdout"
  printf '%s\n' "----------------"
  fail "plain defaults prompt emits selected row id"
fi

bootstrap_git_bin="$TEST_TMP/bootstrap-git-bin"
bootstrap_git_log="$TEST_TMP/bootstrap-git.log"
bootstrap_success_home="$TEST_TMP/bootstrap-success-home"
mkdir -p "$bootstrap_git_bin" "$bootstrap_success_home"
cat >"$bootstrap_git_bin/git" <<EOF
#!/bin/bash
if [ "\$1" = "-C" ]; then
  shift 2
fi
printf '%s\n' "\$*" >>"$bootstrap_git_log"
case "\$1" in
  clone)
    dest="\${@: -1}"
    mkdir -p "\$dest/.git"
    cp -R "$ROOT_DIR/rig" "$ROOT_DIR/lib" "$ROOT_DIR/catalog" "\$dest/" || exit 1
    exit 0
    ;;
  config|fetch|checkout|pull)
    exit 0
    ;;
esac
exit 0
EOF
chmod +x "$bootstrap_git_bin/git"
rm -f "$bootstrap_git_log"
out="$TEST_TMP/bootstrap-success.out"
# shellcheck disable=SC2016
HOME="$bootstrap_success_home" PATH="$fake_darwin_bin:$bootstrap_git_bin:$fake_brew_bin:/usr/bin:/bin" RIG_LOGIN_SHELL=/bin/zsh run_capture "$out" bash -c '
  category_count=$(awk -F "\t" "NR>1 && !seen[\$1]++ { count++ } END { print count }" "'"$ROOT_DIR"'/catalog/tools.tsv")
  {
    i=0
    while [ "$i" -lt "$category_count" ]; do
      printf "\n"
      i=$((i + 1))
    done
    printf "\n"
    printf "\n"
    printf "y\n"
  } | RIG_ALLOW_NON_TTY_PROMPTS=yes ./install.sh
'
assert_success "$?" "install.sh bootstrap succeeds with fake git"
assert_contains "$out" "rig command installed at" "bootstrap success reports installed command"
assert_contains "$out" "Starting rig install" "bootstrap starts rig install"
assert_contains "$out" "Review selection" "bootstrap install flow shows final review"
assert_contains "$out" "Wrote rig config" "bootstrap install flow writes config"
assert_success "$([ -L "$bootstrap_success_home/.local/bin/rig" ] && echo 0 || echo 1)" "bootstrap creates rig symlink"
assert_contains "$bootstrap_git_log" "clone" "bootstrap invokes git clone"

bootstrap_mismatch_git_bin="$TEST_TMP/bootstrap-mismatch-git-bin"
bootstrap_mismatch_git_log="$TEST_TMP/bootstrap-mismatch-git.log"
bootstrap_mismatch_home="$TEST_TMP/bootstrap-mismatch-home"
bootstrap_mismatch_marker="$TEST_TMP/bootstrap-mismatch-marker"
mkdir -p "$bootstrap_mismatch_git_bin" "$bootstrap_mismatch_home/.local/share/rig/.git"
cat >"$bootstrap_mismatch_git_bin/git" <<EOF
#!/bin/bash
if [ "\$1" = "-C" ]; then
  shift 2
fi
printf '%s\n' "\$*" >>"$bootstrap_mismatch_git_log"
case "\$1:\$2:\$3" in
  remote:get-url:origin)
    printf 'file:///tmp/evil-rig.git\n'
    exit 0
    ;;
  config:--get:rig.expectedOrigin)
    printf 'https://github.com/vnedyalk0v/rig.git\n'
    exit 0
    ;;
esac
case "\$1" in
  fetch|checkout|pull|config)
    exit 0
    ;;
esac
exit 0
EOF
chmod +x "$bootstrap_mismatch_git_bin/git"
cat >"$bootstrap_mismatch_home/.local/share/rig/rig" <<EOF
#!/bin/bash
touch "$bootstrap_mismatch_marker"
exit 0
EOF
chmod +x "$bootstrap_mismatch_home/.local/share/rig/rig"
out="$TEST_TMP/bootstrap-existing-origin-mismatch.out"
rm -f "$bootstrap_mismatch_git_log" "$bootstrap_mismatch_marker"
HOME="$bootstrap_mismatch_home" PATH="$fake_darwin_bin:$bootstrap_mismatch_git_bin:/usr/bin:/bin" run_capture "$out" ./install.sh
assert_failure "$?" "install.sh rejects existing clone origin mismatches"
assert_contains "$out" "existing rig clone origin mismatch" "bootstrap origin mismatch is reported"
assert_not_contains "$bootstrap_mismatch_git_log" "fetch" "bootstrap origin mismatch does not fetch"
if [ -e "$bootstrap_mismatch_marker" ]; then
  fail "bootstrap origin mismatch does not execute existing rig"
else
  pass "bootstrap origin mismatch does not execute existing rig"
fi

bootstrap_match_git_bin="$TEST_TMP/bootstrap-match-git-bin"
bootstrap_match_git_log="$TEST_TMP/bootstrap-match-git.log"
bootstrap_match_home="$TEST_TMP/bootstrap-match-home"
bootstrap_match_marker="$TEST_TMP/bootstrap-match-marker"
mkdir -p "$bootstrap_match_git_bin" "$bootstrap_match_home/.local/share/rig/.git"
cat >"$bootstrap_match_git_bin/git" <<EOF
#!/bin/bash
if [ "\$1" = "-C" ]; then
  shift 2
fi
printf '%s\n' "\$*" >>"$bootstrap_match_git_log"
case "\$1:\$2:\$3" in
  remote:get-url:origin)
    printf 'git@github.com:vnedyalk0v/rig.git\n'
    exit 0
    ;;
esac
case "\$1" in
  config|fetch|checkout|pull)
    exit 0
    ;;
esac
exit 0
EOF
chmod +x "$bootstrap_match_git_bin/git"
cat >"$bootstrap_match_home/.local/share/rig/rig" <<EOF
#!/bin/bash
touch "$bootstrap_match_marker"
exit 0
EOF
chmod +x "$bootstrap_match_home/.local/share/rig/rig"
out="$TEST_TMP/bootstrap-existing-origin-match.out"
rm -f "$bootstrap_match_git_log" "$bootstrap_match_marker"
HOME="$bootstrap_match_home" PATH="$fake_darwin_bin:$bootstrap_match_git_bin:/usr/bin:/bin" run_capture "$out" ./install.sh --repo-url https://github.com/vnedyalk0v/rig.git
assert_success "$?" "install.sh accepts existing clone when canonical origins match"
assert_contains "$bootstrap_match_git_log" "fetch origin main" "bootstrap matching origin fetches"
if [ -e "$bootstrap_match_marker" ]; then
  pass "bootstrap matching origin executes rig"
else
  fail "bootstrap matching origin executes rig"
fi

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

out="$TEST_TMP/shell-marker-constants.out"
RIG_ROOT="$ROOT_DIR" bash -c '
  . "'"$ROOT_DIR"'/lib/rig/shell.sh"
  RIG_SHELL_MARKER_START="# >>> custom rig >>>"
  RIG_SHELL_MARKER_END="# <<< custom rig <<<"
  rig_shell_managed_block_content zsh
' >"$out" 2>&1
assert_success "$?" "shell managed block renders with custom markers"
assert_contains "$out" "# >>> custom rig >>>" "shell block start marker uses constant"
assert_contains "$out" "# <<< custom rig <<<" "shell block end marker uses constant"

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
assert_contains "$TEST_TMP/emit-brewfile.out" "cask 'visual-studio-code'" "emit helper includes VS Code"

out="$TEST_TMP/shell-edit-detection.out"
PATH="$fake_darwin_bin:$PATH" RIG_LOGIN_SHELL=/bin/zsh run_capture "$out" ./rig dry-run --select node-npm
assert_success "$?" "dry-run with version-manager selection succeeds"
assert_contains "$out" "Would add managed rig initialization block" "shell-edit detection fires for version-manager selection"

id_prefixed_shell_plan="$TEST_TMP/id-prefixed-shell-plan.tsv"
printf 'id\tstrategy\tpackage\tversion\tlabel\n' >"$id_prefixed_shell_plan"
printf 'id-node\tnvm\tnvm\tlatest\tId Node\n' >>"$id_prefixed_shell_plan"
out="$TEST_TMP/id-prefixed-shell-edit-count.out"
RIG_ROOT="$ROOT_DIR" bash -c '
  . "'"$ROOT_DIR"'/lib/rig/common.sh"
  . "'"$ROOT_DIR"'/lib/rig/catalog.sh"
  . "'"$ROOT_DIR"'/lib/rig/plan.sh"
  rig_count_shell_edits_from_plan_file "'"$id_prefixed_shell_plan"'"
' >"$out" 2>&1
assert_success "$?" "shell edit count reads id-prefixed install-plan rows"
assert_contains "$out" "1" "shell edit count does not skip id-prefixed rows as headers"

invalid_mas_catalog="$TEST_TMP/invalid-mas-tools.tsv"
{
  printf 'category\tid\tlabel\tkind\tpackage\tdefault\tdescription\tversion_strategy\tversions\tmin_macos\tarch\tnotes\n'
  printf 'productivity\tbad-mas\tBad MAS\tmas\tnot-a-number\tno\tInvalid mas id\thomebrew-latest\t\t\t\t\n'
} >"$invalid_mas_catalog"
out="$TEST_TMP/catalog-invalid-mas.out"
run_capture "$out" ./scripts/validate-catalog.sh --tools "$invalid_mas_catalog"
assert_failure "$?" "catalog validation rejects non-numeric mas ids"
assert_contains "$out" "invalid mas id: not-a-number" "invalid mas id is reported"

invalid_tap_catalog="$TEST_TMP/invalid-tap-tools.tsv"
{
  printf 'category\tid\tlabel\tkind\tpackage\tdefault\tdescription\tversion_strategy\tversions\tmin_macos\tarch\tnotes\n'
  printf 'infra\tbad-tap\tBad Tap\ttap-formula\tmissing-slash\tno\tInvalid tap formula\thomebrew-latest\t\t\t\t\n'
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

self_update_mismatch_git_bin="$TEST_TMP/self-update-mismatch-git-bin"
self_update_mismatch_git_log="$TEST_TMP/self-update-mismatch-git.log"
mkdir -p "$self_update_mismatch_git_bin"
cat >"$self_update_mismatch_git_bin/git" <<EOF
#!/bin/bash
if [ "\$1" = "-C" ]; then
  shift 2
fi
printf '%s\n' "\$*" >>"$self_update_mismatch_git_log"
case "\$1:\$2:\$3" in
  config:--get:rig.expectedOrigin)
    printf 'https://github.com/vnedyalk0v/rig.git\n'
    exit 0
    ;;
  remote:get-url:origin)
    printf 'file:///tmp/evil-rig.git\n'
    exit 0
    ;;
esac
case "\$1" in
  fetch|pull)
    exit 0
    ;;
esac
exit 0
EOF
chmod +x "$self_update_mismatch_git_bin/git"
out="$TEST_TMP/self-update-origin-mismatch.out"
rm -f "$self_update_mismatch_git_log"
PATH="$fake_darwin_bin:$self_update_mismatch_git_bin:$PATH" run_capture "$out" ./rig self-update
assert_failure "$?" "rig self-update rejects origin mismatches"
assert_contains "$out" "rig clone origin mismatch" "self-update origin mismatch is reported"
assert_not_contains "$self_update_mismatch_git_log" "fetch" "self-update origin mismatch does not fetch"
assert_not_contains "$self_update_mismatch_git_log" "pull" "self-update origin mismatch does not pull"

self_update_match_git_bin="$TEST_TMP/self-update-match-git-bin"
self_update_match_git_log="$TEST_TMP/self-update-match-git.log"
mkdir -p "$self_update_match_git_bin"
cat >"$self_update_match_git_bin/git" <<EOF
#!/bin/bash
if [ "\$1" = "-C" ]; then
  shift 2
fi
printf '%s\n' "\$*" >>"$self_update_match_git_log"
case "\$1:\$2:\$3" in
  config:--get:rig.expectedOrigin)
    printf 'https://github.com/vnedyalk0v/rig.git\n'
    exit 0
    ;;
  remote:get-url:origin)
    printf 'git@github.com:vnedyalk0v/rig.git\n'
    exit 0
    ;;
esac
case "\$1:\$2:\$3:\$4" in
  symbolic-ref:--quiet:--short:HEAD)
    printf 'main\n'
    exit 0
    ;;
esac
case "\$1" in
  fetch)
    if [ "\$*" = "fetch origin main" ]; then
      exit 0
    fi
    exit 16
    ;;
  pull)
    if [ "\$*" = "pull --ff-only origin main" ]; then
      exit 0
    fi
    exit 17
    ;;
esac
case "\$1" in
  config)
    exit 0
    ;;
esac
exit 0
EOF
chmod +x "$self_update_match_git_bin/git"
out="$TEST_TMP/self-update-origin-match.out"
rm -f "$self_update_match_git_log"
PATH="$fake_darwin_bin:$self_update_match_git_bin:$PATH" run_capture "$out" ./rig self-update
assert_success "$?" "rig self-update accepts canonical matching origins"
assert_contains "$self_update_match_git_log" "fetch origin main" "self-update pins fetch to validated origin and current branch"
assert_contains "$self_update_match_git_log" "pull --ff-only origin main" "self-update pins pull to validated origin and current branch"

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
