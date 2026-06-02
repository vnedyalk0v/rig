#!/bin/bash

rig_brew_prefix() {
  if [ -d /opt/homebrew/bin ]; then
    printf '/opt/homebrew\n'
  else
    printf '/usr/local\n'
  fi
}

rig_brew_shellenv() {
  local prefix brew_shellenv
  if ! rig_command_exists brew; then
    prefix=$(rig_brew_prefix)
    if [ -x "${prefix}/bin/brew" ]; then
      brew_shellenv=$("${prefix}/bin/brew" shellenv 2>/dev/null) || return 1
      eval "$brew_shellenv"
      return 0
    fi
    return 1
  fi
  brew_shellenv=$(brew shellenv 2>/dev/null) || return 1
  eval "$brew_shellenv"
}

rig_ensure_homebrew() {
  if rig_command_exists brew; then
    rig_brew_shellenv || return 1
    return 0
  fi
  if [ "${RIG_SKIP_HOMEBREW_INSTALL:-}" = "yes" ]; then
    rig_print_error "Homebrew is required but RIG_SKIP_HOMEBREW_INSTALL=yes"
    return 1
  fi
  printf 'Installing Homebrew...\n'
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || return 1
  rig_brew_shellenv || return 1
  if ! rig_command_exists brew; then
    rig_print_error "Homebrew installation finished but brew is not available"
    return 1
  fi
  return 0
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
