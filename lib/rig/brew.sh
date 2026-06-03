#!/bin/bash

rig_brew_prefix() {
  if [ "${RIG_HOMEBREW_PREFIX:-}" != "" ]; then
    printf '%s\n' "$RIG_HOMEBREW_PREFIX"
    return 0
  fi
  if [ -d /opt/homebrew/bin ]; then
    printf '/opt/homebrew\n'
  else
    printf '/usr/local\n'
  fi
}

rig_brew_command_path() {
  local prefix
  if rig_command_exists brew; then
    command -v brew
    return 0
  fi
  prefix=$(rig_brew_prefix)
  if [ -x "${prefix}/bin/brew" ]; then
    printf '%s\n' "${prefix}/bin/brew"
    return 0
  fi
  return 1
}

rig_brew_shellenv() {
  local brew_path brew_shellenv
  if ! brew_path=$(rig_brew_command_path); then
    return 1
  fi
  brew_shellenv=$("$brew_path" shellenv 2>/dev/null) || return 1
  eval "$brew_shellenv"
}

rig_ensure_homebrew() {
  if rig_brew_command_path >/dev/null 2>&1; then
    rig_brew_shellenv || return 1
    return 0
  fi
  if [ "${RIG_SKIP_HOMEBREW_INSTALL:-}" = "yes" ]; then
    rig_print_error "Homebrew is required but RIG_SKIP_HOMEBREW_INSTALL=yes"
    return 1
  fi
  rig_print_error "Homebrew is required but is not installed"
  return 1
}

rig_install_homebrew() {
  if [ "${RIG_SKIP_HOMEBREW_INSTALL:-}" = "yes" ]; then
    rig_print_error "Homebrew is required but RIG_SKIP_HOMEBREW_INSTALL=yes"
    return 1
  fi
  printf 'Installing Homebrew...\n'
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || return 1
  rig_brew_shellenv || return 1
  if ! rig_brew_command_path >/dev/null 2>&1; then
    rig_print_error "Homebrew installation finished but brew is not available"
    return 1
  fi
  return 0
}

rig_homebrew_preflight() {
  local mode auto_approve interactive brew_path
  mode=$1
  auto_approve=$2
  interactive=$3

  if brew_path=$(rig_brew_command_path); then
    rig_brew_shellenv || return 1
    if [ "$mode" = "dry-run" ]; then
      printf '# Homebrew prerequisite preview\n'
      printf 'Homebrew found at %s. No Homebrew installation would be needed.\n\n' "$brew_path"
    else
      printf 'Homebrew found at %s\n' "$brew_path"
    fi
    return 0
  fi

  if [ "$mode" = "dry-run" ]; then
    printf '# Homebrew prerequisite preview\n'
    printf 'Homebrew is required to install selected software.\n'
    if [ "$interactive" = "yes" ]; then
      if rig_prompt_yes_no "Homebrew is missing. Simulate approving Homebrew installation for this dry-run?" no; then
        printf 'Would install Homebrew before showing tool selections.\n\n'
        return 0
      fi
      rig_print_error "Homebrew is required before selecting tools"
      return 1
    fi
    printf 'Homebrew not found. Would ask for approval to install Homebrew before installing selected software.\n\n'
    return 0
  fi

  if [ "$interactive" = "yes" ]; then
    printf 'Homebrew is required to install selected software, but brew was not found.\n'
    if ! rig_prompt_yes_no "Install Homebrew now?" no; then
      rig_print_error "Homebrew is required to install selected software"
      return 1
    fi
    rig_install_homebrew || return 1
    return 0
  fi

  if [ "$auto_approve" = "yes" ]; then
    rig_install_homebrew || return 1
    return 0
  fi

  rig_print_error "Homebrew is required to install selected software; rerun with --yes to install Homebrew non-interactively, or install Homebrew first"
  return 1
}

rig_brew_bundle_apply() {
  local brewfile
  brewfile=$1
  if [ ! -f "$brewfile" ]; then
    rig_print_error "Brewfile not found: $brewfile"
    return 1
  fi
  rig_brew_shellenv || return 1
  brew bundle install --file="$brewfile"
}

rig_update_tools() {
  rig_require_macos || return 1
  if ! rig_command_exists brew; then
    rig_print_error "Homebrew is required for rig update-tools"
    return 1
  fi
  rig_brew_shellenv || return 1
  brew update || return 1
  brew upgrade || return 1
}

rig_setup_auto_update() {
  local tap_name
  rig_brew_shellenv || return 1
  tap_name=domt4/tap
  if ! brew tap | grep -F "$tap_name" >/dev/null 2>&1; then
    brew tap "$tap_name" || return 1
  fi
  brew install homebrew-autoupdate || return 1
  brew autoupdate start --upgrade --cleanup --greedy || return 1
}
