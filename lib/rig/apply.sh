#!/bin/bash

rig_validate_install_plan_row() {
  local id strategy package version row catalog_strategy catalog_package catalog_versions
  id=$1
  strategy=$2
  package=$3
  version=$4

  if ! rig_validate_id "$id"; then
    rig_print_error "install plan: invalid catalog id: $id"
    return 1
  fi
  if ! row=$(rig_lookup_tool "$id"); then
    rig_print_error "install plan: unknown catalog id: $id"
    return 1
  fi
  catalog_strategy=$(rig_record_field "$row" 8)
  catalog_package=$(rig_record_field "$row" 5)
  if [ "$strategy" != "$catalog_strategy" ]; then
    rig_print_error "install plan: strategy mismatch for $id (expected $catalog_strategy, got $strategy)"
    return 1
  fi
  if [ "$package" != "$catalog_package" ]; then
    rig_print_error "install plan: package mismatch for $id"
    return 1
  fi
  catalog_versions=$(rig_record_field "$row" 9)
  if [ "$catalog_versions" != "" ]; then
    if ! rig_validate_tool_version "$id" "$version"; then
      return 1
    fi
  elif [ "$version" != "latest" ]; then
    rig_print_error "install plan: unsupported version for $id: $version"
    return 1
  fi
  case "$strategy" in
    nvm|tenv|bun-installer)
      return 0
      ;;
    *)
      rig_print_error "install plan: unsupported strategy for apply: $strategy (id: $id)"
      return 1
      ;;
  esac
}

rig_apply_nvm() {
  local version
  version=$1
  if [ ! -s "${HOME}/.nvm/nvm.sh" ]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash || return 1
  fi
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh" || return 1
  case "$version" in
    latest)
      nvm install node || return 1
      ;;
    lts)
      nvm install --lts || return 1
      ;;
    *)
      nvm install "$version" || return 1
      ;;
  esac
}

rig_apply_tenv() {
  local package version tool_name
  package=$1
  version=$2
  if ! rig_command_exists tenv; then
    rig_brew_shellenv || return 1
    brew install tenv || return 1
  fi
  tool_name=${package#tenv:}
  case "$version" in
    latest)
      tenv "$tool_name" install latest || return 1
      ;;
    *)
      tenv "$tool_name" install "$version" || return 1
      ;;
  esac
}

rig_apply_bun_installer() {
  local version
  version=$1
  case "$version" in
    latest)
      curl -fsSL https://bun.sh/install | bash || return 1
      ;;
    *)
      curl -fsSL https://bun.sh/install | bash -s "bun-v${version}" || return 1
      ;;
  esac
}

rig_apply_install_plan() {
  local plan_file line id strategy package version _label shell_needed
  plan_file=$1
  shell_needed=no
  if [ ! -f "$plan_file" ]; then
    return 0
  fi
  while IFS= read -r line || [ "$line" != "" ]; do
    case "$line" in
      ""|id*)
        continue
        ;;
    esac
    IFS=$'\t' read -r id strategy package version _label < <(printf '%s\n' "$line")
    if ! rig_validate_install_plan_row "$id" "$strategy" "$package" "$version"; then
      return 1
    fi
    case "$strategy" in
      nvm)
        rig_apply_nvm "$version" || return 1
        ;;
      tenv)
        rig_apply_tenv "$package" "$version" || return 1
        ;;
      bun-installer)
        rig_apply_bun_installer "$version" || return 1
        ;;
      *)
        rig_print_warning "unsupported install-plan strategy: $strategy (id: $id)"
        continue
        ;;
    esac
    if rig_strategy_needs_shell_edit "$strategy"; then
      shell_needed=yes
    fi
  done <"$plan_file"
  if [ "$shell_needed" = "yes" ]; then
    if profile_path=$(rig_profile_path 2>/dev/null); then
      rig_shell_apply_managed_block "$profile_path" || return 1
    else
      rig_print_warning "shell profile edits skipped: unsupported login shell"
    fi
  fi
}

rig_apply_macos_defaults() {
  local script_path
  script_path=$1
  if [ ! -f "$script_path" ]; then
    return 0
  fi
  if [ ! -s "$script_path" ]; then
    return 0
  fi
  bash "$script_path"
}

rig_apply_install() {
  local brewfile plan_file defaults_script
  brewfile=$(rig_brewfile_path)
  plan_file=$(rig_install_plan_path)
  defaults_script=$(rig_macos_defaults_path)

  rig_validate_catalogs || return 1

  if [ -f "$brewfile" ] && grep -v '^[[:space:]]*#' "$brewfile" | grep -v '^[[:space:]]*$' >/dev/null 2>&1; then
    rig_ensure_homebrew || return 1
    rig_brew_bundle_apply "$brewfile" || return 1
  fi
  rig_apply_install_plan "$plan_file" || return 1
  rig_apply_macos_defaults "$defaults_script" || return 1
}
