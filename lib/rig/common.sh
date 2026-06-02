#!/bin/bash

RIG_VERSION=${RIG_VERSION:-0.1.0}

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

rig_usage() {
  cat <<'EOF'
Usage:
  rig install [--dry-run] [--select <ids>] [--defaults <ids>] [--category <id>]
  rig dry-run [--select <ids>] [--defaults <ids>] [--category <id>]
  rig list [--category <id>]
  rig doctor
  rig self-update
  rig version
  rig help

Notes:
  --select accepts comma-separated catalog ids.
  --defaults accepts comma-separated macOS defaults ids.
  Real package installs are deferred in this MVP.
EOF
}

rig_resolve_root() {
  source_path=$1
  while [ -L "$source_path" ]; do
    source_dir=$(CDPATH='' cd -P -- "$(dirname -- "$source_path")" && pwd)
    target_path=$(readlink "$source_path")
    case "$target_path" in
      /*) source_path=$target_path ;;
      *) source_path=$source_dir/$target_path ;;
    esac
  done
  CDPATH='' cd -P -- "$(dirname -- "$source_path")" && pwd
}

rig_profile_path() {
  if [ "${HOME:-}" = "" ]; then
    return 1
  fi
  shell_name=$(basename "${SHELL:-}")
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

rig_join_csv_as_lines() {
  value=$1
  old_ifs=$IFS
  IFS=,
  for item in $value; do
    IFS=$old_ifs
    if [ "$item" != "" ]; then
      printf '%s\n' "$item"
    fi
    IFS=,
  done
  IFS=$old_ifs
}
