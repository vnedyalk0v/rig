#!/bin/bash

RIG_VERSION=${RIG_VERSION:-0.1.0}

# Used by lib/rig/plan.sh and rig after sourcing this file.
# shellcheck disable=SC2034
RIG_INSTALL_USAGE='Usage: rig install [--dry-run] [--write-config-only] [--from-config] [--select <ids>] [--defaults <ids>] [--category <id>] [--version <id=version>] [--brewfile <path>] [--install-plan <path>] [--auto-update]'
# shellcheck disable=SC2034
RIG_INSTALL_DESCRIPTION='Run without flags for an interactive install.'

rig_print_error() {
  printf 'rig: %s\n' "$*" >&2
}

rig_print_warning() {
  printf 'rig: warning: %s\n' "$*" >&2
}

rig_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

rig_is_macos() {
  [ "$(uname -s 2>/dev/null)" = "Darwin" ]
}

rig_require_macos() {
  local os_name
  os_name=$(uname -s 2>/dev/null)
  if [ "$os_name" != "Darwin" ]; then
    rig_print_error "rig supports macOS only; detected $os_name"
    return 1
  fi
  return 0
}

rig_usage() {
  cat <<'EOF'
Usage:
  rig install [--dry-run] [--write-config-only] [--from-config] [--select <ids>] [--defaults <ids>] [--category <id>] [--version <id=version>] [--brewfile <path>] [--install-plan <path>] [--auto-update]
  rig dry-run [--select <ids>] [--defaults <ids>] [--category <id>] [--version <id=version>]
  rig list [--category <id>]
  rig doctor
  rig self-update
  rig update-tools
  rig version
  rig help

Notes:
  --select accepts comma-separated catalog ids (optional id=version).
  --defaults accepts comma-separated macOS defaults ids.
  Run rig install with no flags for an interactive install.
EOF
}

rig_login_shell() {
  local shell_path username
  if [ "${RIG_LOGIN_SHELL:-}" != "" ]; then
    printf '%s\n' "$RIG_LOGIN_SHELL"
    return 0
  fi
  if rig_is_macos; then
    username=$(id -un 2>/dev/null)
    if [ "$username" != "" ] && rig_command_exists dscl; then
      shell_path=$(dscl . -read "/Users/$username" UserShell 2>/dev/null | awk '{print $NF}')
      if [ "$shell_path" != "" ]; then
        printf '%s\n' "$shell_path"
        return 0
      fi
    fi
  fi
  if [ "${SHELL:-}" != "" ]; then
    printf '%s\n' "$SHELL"
    return 0
  fi
  return 1
}

rig_escape_brew_string() {
  local value char escaped
  value=$1
  escaped=
  while [ "$value" != "" ]; do
    char=${value%"${value#?}"}
    value=${value#?}
    case "$char" in
      \\) escaped="${escaped}\\\\" ;;
      \") escaped="${escaped}\\\"" ;;
      *) escaped="${escaped}${char}" ;;
    esac
  done
  printf '%s' "$escaped"
}

rig_profile_path() {
  local shell_path shell_name
  if [ "${HOME:-}" = "" ]; then
    return 1
  fi
  if ! shell_path=$(rig_login_shell); then
    return 1
  fi
  shell_name=$(basename "$shell_path")
  case "$shell_name" in
    zsh)
      printf '%s\n' "${HOME}/.zshrc"
      ;;
    bash)
      printf '%s\n' "${HOME}/.bash_profile"
      ;;
    *)
      return 1
      ;;
  esac
}

rig_seen_contains() {
  local seen wanted
  seen=$1
  wanted=$2
  case "$seen" in
    *"
$wanted
"*)
      return 0
      ;;
  esac
  return 1
}

rig_join_csv_as_lines() {
  local value old_ifs glob_was_disabled item
  value=$1
  old_ifs=$IFS
  case "$-" in
    *f*) glob_was_disabled=yes ;;
    *) glob_was_disabled=no ;;
  esac
  set -f
  IFS=,
  for item in $value; do
    IFS=$old_ifs
    if [ "$item" != "" ]; then
      printf '%s\n' "$item"
    fi
    IFS=,
  done
  IFS=$old_ifs
  if [ "$glob_was_disabled" = "no" ]; then
    set +f
  fi
}

rig_args_include() {
  local wanted arg
  wanted=$1
  shift
  for arg in "$@"; do
    if [ "$arg" = "$wanted" ]; then
      return 0
    fi
  done
  return 1
}

rig_strategy_needs_shell_edit() {
  case "$1" in
    nvm|tenv|bun-installer)
      return 0
      ;;
  esac
  return 1
}

rig_handle_command_help() {
  local command_label usage_line description unknown_arg
  command_label=$1
  usage_line=$2
  description=$3
  shift 3
  if [ "$#" -eq 0 ]; then
    return 0
  fi
  case "$1" in
    --help|-h)
      if [ "$#" -gt 1 ]; then
        rig_print_error "unknown $command_label argument: $2"
        return 1
      fi
      printf '%s\n' "$usage_line"
      printf '%s\n' "$description"
      return 0
      ;;
    *)
      unknown_arg=$1
      rig_print_error "unknown $command_label argument: $unknown_arg"
      return 1
      ;;
  esac
}
