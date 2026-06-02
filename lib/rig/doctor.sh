#!/bin/bash

rig_doctor() {
  local failures home_path login_shell
  failures=0

  printf 'rig doctor\n'

  if rig_is_macos; then
    printf 'ok: macOS detected (%s)\n' "$(uname -s)"
  else
    printf 'error: rig supports macOS only; detected %s\n' "$(uname -s 2>/dev/null)"
    failures=$((failures + 1))
  fi

  case "${BASH_VERSION:-}" in
    3.2.*)
      printf 'ok: Bash %s\n' "$BASH_VERSION"
      ;;
    "")
      printf 'warning: BASH_VERSION is not set\n'
      ;;
    *)
      printf 'ok: Bash %s (scripts remain Bash 3.2-compatible)\n' "$BASH_VERSION"
      ;;
  esac

  if rig_command_exists git; then
    printf 'ok: git found at %s\n' "$(command -v git)"
  else
    printf 'error: git is required for bootstrap and self-update\n'
    failures=$((failures + 1))
  fi

  if rig_command_exists brew; then
    printf 'ok: Homebrew found at %s\n' "$(command -v brew)"
  else
    printf 'warning: Homebrew not found; real package installs are not implemented in this MVP\n'
  fi

  if rig_profile_path >/dev/null 2>&1; then
    printf 'ok: supported login shell profile target: %s\n' "$(rig_profile_path)"
  else
    if ! login_shell=$(rig_login_shell); then
      login_shell=unknown
    fi
    printf 'warning: unsupported login shell: %s\n' "$(basename "$login_shell")"
  fi

  if rig_validate_catalogs >/dev/null 2>&1; then
    printf 'ok: catalogs are valid\n'
  else
    printf 'error: catalog validation failed\n'
    rig_validate_catalogs
    failures=$((failures + 1))
  fi

  home_path=${HOME:-unset}
  if [ "$home_path" != "unset" ] && [ -d "$home_path" ] && [ -w "$home_path" ]; then
    printf 'ok: HOME is writable: %s\n' "$home_path"
  else
    printf 'warning: HOME is not writable: %s\n' "$home_path"
  fi

  if [ "$failures" -eq 0 ]; then
    printf 'doctor completed with no blocking issues\n'
    return 0
  fi

  printf 'doctor found %s blocking issue(s)\n' "$failures"
  return 1
}
