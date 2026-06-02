#!/bin/bash

rig_print_list() {
  local category_filter
  local category id label kind package default_flag description version_strategy _versions _notes
  category_filter=

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --category)
        if [ "$#" -lt 2 ]; then
          rig_print_error "--category requires a value"
          return 1
        fi
        category_filter=$2
        shift 2
        ;;
      --help|-h)
        printf 'Usage: rig list [--category <id>]\n'
        return 0
        ;;
      *)
        rig_print_error "unknown list argument: $1"
        return 1
        ;;
    esac
  done

  rig_validate_catalogs || return 1

  printf 'category\tid\tlabel\tkind\tpackage\tdefault\tversion_strategy\tdescription\n'
  while IFS="$RIG_TSV_DELIMITER" read -r category id label kind package default_flag description version_strategy _versions _notes; do
    if [ "$category_filter" != "" ] && [ "$category" != "$category_filter" ]; then
      continue
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$category" "$id" "$label" "$kind" "$package" "$default_flag" "$version_strategy" "$description"
  done <<EOF
$(rig_each_tool)
EOF
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

rig_collect_selected_tools() {
  local select_arg category_filter seen selected_id row
  local category id _id _label _kind _package default_flag _default_flag _description _version_strategy _versions _notes
  select_arg=$1
  category_filter=$2
  seen='
'

  if [ "$select_arg" != "" ]; then
    while IFS= read -r selected_id || [ "$selected_id" != "" ]; do
      if [ "$selected_id" = "" ]; then
        continue
      fi
      if ! rig_validate_id "$selected_id"; then
        rig_print_error "invalid catalog id: $selected_id"
        return 1
      fi
      if rig_seen_contains "$seen" "$selected_id"; then
        rig_print_error "duplicate catalog id selected: $selected_id"
        return 1
      fi
      if ! row=$(rig_lookup_tool "$selected_id"); then
        rig_print_error "unknown catalog id: $selected_id"
        return 1
      fi
      IFS="$RIG_TSV_DELIMITER" read -r category _id _label _kind _package _default_flag _description _version_strategy _versions _notes <<EOF
$row
EOF
      if [ "$category_filter" != "" ] && [ "$category" != "$category_filter" ]; then
        rig_print_error "catalog id $selected_id is not in category $category_filter"
        return 1
      fi
      printf '%s\n' "$selected_id"
      seen="${seen}${selected_id}
"
    done <<EOF
$(rig_join_csv_as_lines "$select_arg")
EOF
    return 0
  fi

  while IFS="$RIG_TSV_DELIMITER" read -r category id _label _kind _package default_flag _description _version_strategy _versions _notes; do
    if [ "$category_filter" != "" ] && [ "$category" != "$category_filter" ]; then
      continue
    fi
    if [ "$default_flag" = "yes" ]; then
      printf '%s\n' "$id"
    fi
  done <<EOF
$(rig_each_tool)
EOF
}

rig_collect_selected_defaults() {
  local defaults_arg seen selected_id
  defaults_arg=$1
  seen='
'

  if [ "$defaults_arg" = "" ]; then
    return 0
  fi

  while IFS= read -r selected_id || [ "$selected_id" != "" ]; do
    if [ "$selected_id" = "" ]; then
      continue
    fi
    if ! rig_validate_id "$selected_id"; then
      rig_print_error "invalid macOS default id: $selected_id"
      return 1
    fi
    if rig_seen_contains "$seen" "$selected_id"; then
      rig_print_error "duplicate macOS default id selected: $selected_id"
      return 1
    fi
    if ! rig_default_exists "$selected_id"; then
      rig_print_error "unknown macOS default id: $selected_id"
      return 1
    fi
    printf '%s\n' "$selected_id"
    seen="${seen}${selected_id}
"
  done <<EOF
$(rig_join_csv_as_lines "$defaults_arg")
EOF
}

rig_default_version() {
  local versions first
  versions=$1
  first=${versions%%,*}
  if [ "$first" != "" ]; then
    printf '%s\n' "$first"
  else
    printf 'latest\n'
  fi
}

rig_render_brewfile_line() {
  local kind package label tap_name formula_name
  kind=$1
  package=$2
  label=$3

  case "$kind" in
    formula)
      printf 'brew "%s"\n' "$(rig_escape_brew_string "$package")"
      ;;
    cask)
      printf 'cask "%s"\n' "$(rig_escape_brew_string "$package")"
      ;;
    mas)
      printf 'mas "%s", id: %s\n' "$(rig_escape_brew_string "$label")" "$package"
      ;;
    vscode)
      printf 'vscode "%s"\n' "$(rig_escape_brew_string "$package")"
      ;;
    tap-formula)
      tap_name=$(rig_escape_brew_string "${package%/*}")
      formula_name=$(rig_escape_brew_string "${package##*/}")
      printf 'tap "%s"\n' "$tap_name"
      printf 'brew "%s"\n' "$formula_name"
      ;;
  esac
}

rig_render_dry_run() {
  local select_arg defaults_arg category_filter selected_tools selected_defaults
  local brewfile_count external_count shell_edit_count defaults_count
  local selected_id selected_default row profile_path selected_version login_shell
  local _category _id id label kind package _default_flag _description
  local _version_strategy version_strategy _versions versions _notes
  local _label command_text _restart_hint
  select_arg=
  defaults_arg=
  category_filter=

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run)
        shift
        ;;
      --select)
        if [ "$#" -lt 2 ]; then
          rig_print_error "--select requires a value"
          return 1
        fi
        select_arg=$2
        shift 2
        ;;
      --defaults)
        if [ "$#" -lt 2 ]; then
          rig_print_error "--defaults requires a value"
          return 1
        fi
        defaults_arg=$2
        shift 2
        ;;
      --category)
        if [ "$#" -lt 2 ]; then
          rig_print_error "--category requires a value"
          return 1
        fi
        category_filter=$2
        shift 2
        ;;
      --help|-h)
        printf 'Usage: rig dry-run [--select <ids>] [--defaults <ids>] [--category <id>]\n'
        return 0
        ;;
      *)
        rig_print_error "unknown dry-run argument: $1"
        return 1
        ;;
    esac
  done

  rig_validate_catalogs || return 1

  if ! selected_tools=$(rig_collect_selected_tools "$select_arg" "$category_filter"); then
    return 1
  fi
  if ! selected_defaults=$(rig_collect_selected_defaults "$defaults_arg"); then
    return 1
  fi

  printf 'rig dry-run\n'
  printf 'No packages, config files, shell files, defaults, or LaunchAgents will be changed.\n\n'

  printf '# Brewfile preview\n'
  brewfile_count=0
  while IFS= read -r selected_id || [ "$selected_id" != "" ]; do
    if [ "$selected_id" = "" ]; then
      continue
    fi
    row=$(rig_lookup_tool "$selected_id")
    IFS="$RIG_TSV_DELIMITER" read -r _category _id label kind package _default_flag _description _version_strategy _versions _notes <<EOF
$row
EOF
    case "$kind" in
      formula|cask|tap-formula|mas|vscode)
        rig_render_brewfile_line "$kind" "$package" "$label"
        brewfile_count=$((brewfile_count + 1))
        ;;
    esac
  done <<EOF
$selected_tools
EOF
  if [ "$brewfile_count" -eq 0 ]; then
    printf 'No Homebrew-native packages selected.\n'
  fi
  printf '\n'

  printf '# External install plan preview\n'
  external_count=0
  shell_edit_count=0
  while IFS= read -r selected_id || [ "$selected_id" != "" ]; do
    if [ "$selected_id" = "" ]; then
      continue
    fi
    row=$(rig_lookup_tool "$selected_id")
    IFS="$RIG_TSV_DELIMITER" read -r _category id label kind package _default_flag _description version_strategy versions _notes <<EOF
$row
EOF
    case "$kind" in
      external|version-manager)
        selected_version=$(rig_default_version "$versions")
        printf '%s\t%s\t%s\t%s\n' "$id" "$package" "$selected_version" "$label"
        external_count=$((external_count + 1))
        case "$version_strategy" in
          nvm|tenv|bun-installer)
            shell_edit_count=$((shell_edit_count + 1))
            ;;
        esac
        ;;
    esac
  done <<EOF
$selected_tools
EOF
  if [ "$external_count" -eq 0 ]; then
    printf 'No external installers selected.\n'
  fi
  printf '\n'

  printf '# macOS defaults preview\n'
  defaults_count=0
  while IFS= read -r selected_default || [ "$selected_default" != "" ]; do
    if [ "$selected_default" = "" ]; then
      continue
    fi
    row=$(rig_lookup_default "$selected_default")
    IFS="$RIG_TSV_DELIMITER" read -r _id _label _description command_text _restart_hint <<EOF
$row
EOF
    printf '%s\n' "$command_text"
    defaults_count=$((defaults_count + 1))
  done <<EOF
$selected_defaults
EOF
  if [ "$defaults_count" -eq 0 ]; then
    printf 'No macOS defaults selected.\n'
  fi
  printf '\n'

  printf '# Shell/profile edits preview\n'
  if profile_path=$(rig_profile_path 2>/dev/null); then
    if [ "$shell_edit_count" -gt 0 ]; then
      printf 'Would add managed rig initialization block to %s.\n' "$profile_path"
    else
      printf 'No shell/profile edits selected.\n'
    fi
  else
    if login_shell=$(rig_login_shell 2>/dev/null); then
      printf 'Unsupported login shell: %s. rig would warn instead of editing shell files.\n' "$(basename "$login_shell")"
    else
      printf 'Unsupported login shell: unknown. rig would warn instead of editing shell files.\n'
    fi
  fi
}
