#!/bin/bash

rig_config_dir() {
  if [ "${RIG_CONFIG_DIR:-}" != "" ]; then
    printf '%s\n' "$RIG_CONFIG_DIR"
    return 0
  fi
  if [ "${XDG_CONFIG_HOME:-}" != "" ]; then
    printf '%s/rig\n' "$XDG_CONFIG_HOME"
  else
    printf '%s\n' "${HOME:-}/.config/rig"
  fi
}

rig_brewfile_path() {
  if [ "${RIG_BREWFILE:-}" != "" ]; then
    printf '%s\n' "$RIG_BREWFILE"
  else
    printf '%s/Brewfile\n' "$(rig_config_dir)"
  fi
}

rig_install_plan_path() {
  if [ "${RIG_INSTALL_PLAN:-}" != "" ]; then
    printf '%s\n' "$RIG_INSTALL_PLAN"
  else
    printf '%s/install-plan.tsv\n' "$(rig_config_dir)"
  fi
}

rig_macos_defaults_path() {
  if [ "${RIG_MACOS_DEFAULTS:-}" != "" ]; then
    printf '%s\n' "$RIG_MACOS_DEFAULTS"
  else
    printf '%s/macos-defaults.sh\n' "$(rig_config_dir)"
  fi
}

rig_config_ensure_dir() {
  local config_dir
  config_dir=$(rig_config_dir)
  if [ "$config_dir" = "" ] || [ "$config_dir" = "/.config/rig" ]; then
    rig_print_error "HOME is required to write rig config"
    return 1
  fi
  mkdir -p "$config_dir" || return 1
}

rig_config_write_atomic() {
  local target_path content tmp_path target_dir
  target_path=$1
  content=$2
  target_dir=$(dirname -- "$target_path")
  mkdir -p "$target_dir" || return 1
  tmp_path=$(mktemp "${target_dir}/.rig-write.XXXXXX") || return 1
  printf '%s' "$content" >"$tmp_path" || {
    rm -f "$tmp_path"
    return 1
  }
  mv -f "$tmp_path" "$target_path"
}

rig_config_exists() {
  if [ -f "$(rig_brewfile_path)" ] || [ -f "$(rig_install_plan_path)" ] || [ -f "$(rig_macos_defaults_path)" ]; then
    return 0
  fi
  return 1
}
