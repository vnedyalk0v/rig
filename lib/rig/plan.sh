#!/bin/bash

rig_print_list() {
  local category_filter category_seen
  local category id label kind package default_flag description version_strategy _versions _notes
  category_filter=
  category_seen=no

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --category)
        if [ "$#" -lt 2 ]; then
          rig_print_error "--category requires a value"
          return 1
        fi
        if [ "$category_seen" = "yes" ]; then
          rig_print_error "repeated --category is not supported"
          return 1
        fi
        category_seen=yes
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
  if [ "$category_filter" != "" ] && ! rig_tool_category_exists "$category_filter"; then
    rig_print_error "unknown category: $category_filter"
    return 1
  fi

  printf 'category\tid\tlabel\tkind\tpackage\tdefault\tversion_strategy\tdescription\n'
  while IFS="$RIG_TSV_DELIMITER" read -r category id label kind package default_flag description version_strategy _versions _notes; do
    if [ "$category_filter" != "" ] && [ "$category" != "$category_filter" ]; then
      continue
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$category" "$id" "$label" "$kind" "$package" "$default_flag" "$version_strategy" "$description"
  done < <(rig_each_tool)
}

rig_split_select_token() {
  local token tool_id tool_version
  token=$1
  tool_id=${token%%=*}
  if [ "$tool_id" = "$token" ]; then
    RIG_SELECT_TOOL_ID=$tool_id
    RIG_SELECT_TOOL_VERSION=
  else
    tool_version=${token#*=}
    if [ "$tool_version" = "" ]; then
      rig_print_error "invalid catalog id: $token"
      return 1
    fi
    RIG_SELECT_TOOL_ID=$tool_id
    RIG_SELECT_TOOL_VERSION=$tool_version
  fi
  return 0
}

rig_version_map_set() {
  local map tool_id version
  map=$1
  tool_id=$2
  version=$3
  if [ "$map" != "" ]; then
    printf '%s\n' "$map"
  fi
  printf '%s=%s\n' "$tool_id" "$version"
}

rig_version_map_lookup() {
  local map tool_id line entry_id entry_version
  map=$1
  tool_id=$2
  while IFS= read -r line || [ "$line" != "" ]; do
    if [ "$line" = "" ]; then
      continue
    fi
    entry_id=${line%%=*}
    entry_version=${line#*=}
    if [ "$entry_id" = "$line" ]; then
      continue
    fi
    if [ "$entry_id" = "$tool_id" ]; then
      printf '%s\n' "$entry_version"
      return 0
    fi
  done < <(printf '%s\n' "$map")
  return 1
}

rig_parse_version_args() {
  local versions_arg map entry
  versions_arg=$1
  map=
  while IFS= read -r entry || [ "$entry" != "" ]; do
    if [ "$entry" = "" ]; then
      continue
    fi
    if ! rig_split_select_token "$entry"; then
      return 1
    fi
    if ! rig_validate_id "$RIG_SELECT_TOOL_ID"; then
      rig_print_error "invalid version map id: $RIG_SELECT_TOOL_ID"
      return 1
    fi
    if [ "$RIG_SELECT_TOOL_VERSION" = "" ]; then
      rig_print_error "invalid version entry (expected id=version): $entry"
      return 1
    fi
    if ! rig_validate_tool_version "$RIG_SELECT_TOOL_ID" "$RIG_SELECT_TOOL_VERSION"; then
      return 1
    fi
    map=$(rig_version_map_set "$map" "$RIG_SELECT_TOOL_ID" "$RIG_SELECT_TOOL_VERSION")
  done < <(rig_join_csv_as_lines "$versions_arg")
  printf '%s' "$map"
}

rig_prepare_plan_selections() {
  rig_require_macos || return 1
  rig_validate_catalogs || return 1
  if [ "$RIG_PLAN_CATEGORY" != "" ] && ! rig_tool_category_exists "$RIG_PLAN_CATEGORY"; then
    rig_print_error "unknown category: $RIG_PLAN_CATEGORY"
    return 1
  fi
  rig_resolve_plan_selections || return 1
}

rig_collect_inline_select_versions() {
  local select_arg version_map selected_token tool_id
  select_arg=$1
  version_map=$2

  if [ "$select_arg" = "" ]; then
    printf '%s' "$version_map"
    return 0
  fi

  while IFS= read -r selected_token || [ "$selected_token" != "" ]; do
    if [ "$selected_token" = "" ]; then
      continue
    fi
    if ! rig_split_select_token "$selected_token"; then
      return 1
    fi
    if [ "$RIG_SELECT_TOOL_VERSION" = "" ]; then
      continue
    fi
    tool_id=$RIG_SELECT_TOOL_ID
    if ! rig_validate_id "$tool_id"; then
      rig_print_error "invalid catalog id: $tool_id"
      return 1
    fi
    if rig_version_map_lookup "$version_map" "$tool_id" >/dev/null 2>&1; then
      continue
    fi
    if ! rig_validate_tool_version "$tool_id" "$RIG_SELECT_TOOL_VERSION"; then
      return 1
    fi
    version_map=$(rig_version_map_set "$version_map" "$tool_id" "$RIG_SELECT_TOOL_VERSION")
  done < <(rig_join_csv_as_lines "$select_arg")

  printf '%s' "$version_map"
}

rig_collect_selected_tools() {
  local select_arg category_filter seen selected_token tool_id row
  local category id _id _label _kind _package default_flag _default_flag _description _version_strategy _versions _notes
  select_arg=$1
  category_filter=$2
  seen='
'

  if [ "$select_arg" != "" ]; then
    while IFS= read -r selected_token || [ "$selected_token" != "" ]; do
      if [ "$selected_token" = "" ]; then
        continue
      fi
      if ! rig_split_select_token "$selected_token"; then
        return 1
      fi
      tool_id=$RIG_SELECT_TOOL_ID
      if ! rig_validate_id "$tool_id"; then
        rig_print_error "invalid catalog id: $tool_id"
        return 1
      fi
      if rig_seen_contains "$seen" "$tool_id"; then
        rig_print_error "duplicate catalog id selected: $tool_id"
        return 1
      fi
      if ! row=$(rig_lookup_tool "$tool_id"); then
        rig_print_error "unknown catalog id: $tool_id"
        return 1
      fi
      IFS="$RIG_TSV_DELIMITER" read -r category _id _label _kind _package _default_flag _description _version_strategy _versions _notes < <(printf '%s\n' "$row")
      if [ "$category_filter" != "" ] && [ "$category" != "$category_filter" ]; then
        rig_print_error "catalog id $tool_id is not in category $category_filter"
        return 1
      fi
      printf '%s\n' "$tool_id"
      seen="${seen}${tool_id}
"
    done < <(rig_join_csv_as_lines "$select_arg")
    return 0
  fi

  while IFS="$RIG_TSV_DELIMITER" read -r category id _label _kind _package default_flag _description _version_strategy _versions _notes; do
    if [ "$category_filter" != "" ] && [ "$category" != "$category_filter" ]; then
      continue
    fi
    if [ "$default_flag" = "yes" ]; then
      printf '%s\n' "$id"
    fi
  done < <(rig_each_tool)
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
  done < <(rig_join_csv_as_lines "$defaults_arg")
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

rig_resolve_tool_version() {
  local tool_id versions version_map resolved
  tool_id=$1
  versions=$2
  version_map=$3
  if resolved=$(rig_version_map_lookup "$version_map" "$tool_id"); then
    printf '%s\n' "$resolved"
  else
    rig_default_version "$versions"
  fi
}

rig_render_brewfile_line() {
  local kind package label tap_name formula_name
  kind=$1
  package=$2
  label=$3

  case "$kind" in
    formula)
      printf "brew '%s'\n" "$(rig_escape_brew_string "$package")"
      ;;
    cask)
      printf "cask '%s'\n" "$(rig_escape_brew_string "$package")"
      ;;
    mas)
      printf "mas '%s', id: %s\n" "$(rig_escape_brew_string "$label")" "$package"
      ;;
    vscode)
      printf "vscode '%s'\n" "$(rig_escape_brew_string "$package")"
      ;;
    tap-formula)
      tap_name=$(rig_escape_brew_string "${package%/*}")
      formula_name=$(rig_escape_brew_string "${package##*/}")
      printf "tap '%s'\n" "$tap_name"
      printf "brew '%s'\n" "$formula_name"
      ;;
  esac
}

rig_emit_brewfile_content() {
  local selected_tools selected_id row _category _id label kind package _default_flag _description _version_strategy _versions _notes
  selected_tools=$1
  while IFS= read -r selected_id || [ "$selected_id" != "" ]; do
    if [ "$selected_id" = "" ]; then
      continue
    fi
    row=$(rig_lookup_tool "$selected_id")
    IFS="$RIG_TSV_DELIMITER" read -r _category _id label kind package _default_flag _description _version_strategy _versions _notes < <(printf '%s\n' "$row")
    case "$kind" in
      formula|cask|tap-formula|mas|vscode)
        rig_render_brewfile_line "$kind" "$package" "$label"
        ;;
    esac
  done < <(printf '%s\n' "$selected_tools")
}

rig_emit_install_plan() {
  local selected_tools version_map format selected_id row id label kind package version_strategy versions selected_version _category _default_flag _description _notes
  selected_tools=$1
  version_map=$2
  format=$3
  if [ "$format" = "file" ]; then
    printf 'id\tstrategy\tpackage\tversion\tlabel\n'
  fi
  while IFS= read -r selected_id || [ "$selected_id" != "" ]; do
    if [ "$selected_id" = "" ]; then
      continue
    fi
    row=$(rig_lookup_tool "$selected_id")
    IFS="$RIG_TSV_DELIMITER" read -r _category id label kind package _default_flag _description version_strategy versions _notes < <(printf '%s\n' "$row")
    case "$kind" in
      external|version-manager)
        selected_version=$(rig_resolve_tool_version "$id" "$versions" "$version_map")
        if [ "$format" = "file" ]; then
          printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$version_strategy" "$package" "$selected_version" "$label"
        else
          printf '%s\t%s\t%s\t%s\n' "$id" "$package" "$selected_version" "$label"
        fi
        ;;
    esac
  done < <(printf '%s\n' "$selected_tools")
}

rig_emit_install_plan_content() {
  rig_emit_install_plan "$1" "$2" file
}

rig_emit_install_plan_preview() {
  rig_emit_install_plan "$1" "$2" preview
}

rig_emit_macos_defaults() {
  local selected_defaults mode selected_default row _id _label _description domain key value_type value restart_hint restart_cmds
  selected_defaults=$1
  mode=$2
  restart_cmds=
  if [ "$mode" = "script" ]; then
    printf '%s\n' '#!/bin/bash'
    printf '%s\n' '# Generated by rig. Re-runnable macOS preference tweaks.'
  fi
  while IFS= read -r selected_default || [ "$selected_default" != "" ]; do
    if [ "$selected_default" = "" ]; then
      continue
    fi
    row=$(rig_lookup_default "$selected_default")
    IFS="$RIG_TSV_DELIMITER" read -r _id _label _description domain key value_type value restart_hint < <(printf '%s\n' "$row")
    case "$value_type" in
      bool)
        printf "defaults write '%s' '%s' -bool %s\n" "$domain" "$key" "$value"
        ;;
    esac
    if [ "$mode" = "script" ]; then
      case "$restart_hint" in
        *Finder*)
          restart_cmds="${restart_cmds}killall Finder 2>/dev/null || true
"
          ;;
        *Dock*)
          restart_cmds="${restart_cmds}killall Dock 2>/dev/null || true
"
          ;;
      esac
    fi
  done < <(printf '%s\n' "$selected_defaults")
  if [ "$mode" = "script" ] && [ "$restart_cmds" != "" ]; then
    printf '%s\n' "$restart_cmds"
  fi
}

rig_emit_macos_defaults_script() {
  rig_emit_macos_defaults "$1" script
}

rig_emit_macos_defaults_preview() {
  rig_emit_macos_defaults "$1" preview
}

rig_count_shell_edits_needed() {
  local selected_tools selected_id row version_strategy count _category _id _label _kind _package _default_flag _description _versions _notes
  selected_tools=$1
  count=0
  while IFS= read -r selected_id || [ "$selected_id" != "" ]; do
    if [ "$selected_id" = "" ]; then
      continue
    fi
    row=$(rig_lookup_tool "$selected_id")
    IFS="$RIG_TSV_DELIMITER" read -r _category _id _label _kind _package _default_flag _description version_strategy _versions _notes < <(printf '%s\n' "$row")
    if rig_strategy_needs_shell_edit "$version_strategy"; then
      count=$((count + 1))
    fi
  done < <(printf '%s\n' "$selected_tools")
  printf '%s\n' "$count"
}

rig_count_homebrew_selected() {
  local selected_tools selected_id row kind count _category _id _label _package _default_flag _description _version_strategy _versions _notes
  selected_tools=$1
  count=0
  while IFS= read -r selected_id || [ "$selected_id" != "" ]; do
    if [ "$selected_id" = "" ]; then
      continue
    fi
    row=$(rig_lookup_tool "$selected_id")
    IFS="$RIG_TSV_DELIMITER" read -r _category _id _label kind _package _default_flag _description _version_strategy _versions _notes < <(printf '%s\n' "$row")
    case "$kind" in
      formula|cask|tap-formula|mas|vscode)
        count=$((count + 1))
        ;;
    esac
  done < <(printf '%s\n' "$selected_tools")
  printf '%s\n' "$count"
}

rig_count_external_selected() {
  local selected_tools selected_id row kind count _category _id _label _package _default_flag _description _version_strategy _versions _notes
  selected_tools=$1
  count=0
  while IFS= read -r selected_id || [ "$selected_id" != "" ]; do
    if [ "$selected_id" = "" ]; then
      continue
    fi
    row=$(rig_lookup_tool "$selected_id")
    IFS="$RIG_TSV_DELIMITER" read -r _category _id _label kind _package _default_flag _description _version_strategy _versions _notes < <(printf '%s\n' "$row")
    case "$kind" in
      external|version-manager)
        count=$((count + 1))
        ;;
    esac
  done < <(printf '%s\n' "$selected_tools")
  printf '%s\n' "$count"
}

rig_reset_plan_globals() {
  RIG_PLAN_SELECT=
  RIG_PLAN_DEFAULTS=
  RIG_PLAN_CATEGORY=
  RIG_PLAN_VERSION=
  RIG_PLAN_BREWFILE=
  RIG_PLAN_INSTALL_PLAN=
  RIG_PLAN_DRY_RUN=no
  RIG_PLAN_YES=no
  RIG_PLAN_WRITE_CONFIG_ONLY=no
  RIG_PLAN_FROM_CONFIG=no
  RIG_PLAN_AUTO_UPDATE=no
  RIG_PLAN_VERSION_MAP=
  RIG_PLAN_SELECTED_TOOLS=
  RIG_PLAN_SELECTED_DEFAULTS=
  RIG_PLAN_SELECT_SEEN=no
  RIG_PLAN_DEFAULTS_SEEN=no
  RIG_PLAN_CATEGORY_SEEN=no
  RIG_PLAN_VERSION_SEEN=no
  RIG_PLAN_BREWFILE_SEEN=no
  RIG_PLAN_INSTALL_PLAN_SEEN=no
  RIG_PLAN_SHOWED_HELP=no
}

rig_parse_plan_args() {
  local command_name help_text unknown_label
  command_name=$1
  shift
  case "$command_name" in
    dry-run)
      help_text='Usage: rig dry-run [--select <ids>] [--defaults <ids>] [--category <id>] [--version <id=version>]'
      ;;
    install)
      help_text="$RIG_INSTALL_USAGE"
      ;;
    *)
      help_text='Usage: rig plan'
      ;;
  esac

  rig_reset_plan_globals

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run)
        RIG_PLAN_DRY_RUN=yes
        shift
        ;;
      --yes)
        RIG_PLAN_YES=yes
        shift
        ;;
      --write-config-only)
        RIG_PLAN_WRITE_CONFIG_ONLY=yes
        shift
        ;;
      --from-config)
        RIG_PLAN_FROM_CONFIG=yes
        shift
        ;;
      --select)
        if [ "$#" -lt 2 ]; then
          rig_print_error "--select requires a value"
          return 1
        fi
        if [ "$RIG_PLAN_SELECT_SEEN" = "yes" ]; then
          rig_print_error "repeated --select is not supported"
          return 1
        fi
        RIG_PLAN_SELECT_SEEN=yes
        RIG_PLAN_SELECT=$2
        shift 2
        ;;
      --defaults)
        if [ "$#" -lt 2 ]; then
          rig_print_error "--defaults requires a value"
          return 1
        fi
        if [ "$RIG_PLAN_DEFAULTS_SEEN" = "yes" ]; then
          rig_print_error "repeated --defaults is not supported"
          return 1
        fi
        RIG_PLAN_DEFAULTS_SEEN=yes
        RIG_PLAN_DEFAULTS=$2
        shift 2
        ;;
      --category)
        if [ "$#" -lt 2 ]; then
          rig_print_error "--category requires a value"
          return 1
        fi
        if [ "$RIG_PLAN_CATEGORY_SEEN" = "yes" ]; then
          rig_print_error "repeated --category is not supported"
          return 1
        fi
        RIG_PLAN_CATEGORY_SEEN=yes
        RIG_PLAN_CATEGORY=$2
        shift 2
        ;;
      --version)
        if [ "$#" -lt 2 ]; then
          rig_print_error "--version requires a value"
          return 1
        fi
        if [ "$RIG_PLAN_VERSION_SEEN" = "yes" ]; then
          rig_print_error "repeated --version is not supported"
          return 1
        fi
        RIG_PLAN_VERSION_SEEN=yes
        RIG_PLAN_VERSION=$2
        shift 2
        ;;
      --brewfile)
        if [ "$#" -lt 2 ]; then
          rig_print_error "--brewfile requires a value"
          return 1
        fi
        if [ "$RIG_PLAN_BREWFILE_SEEN" = "yes" ]; then
          rig_print_error "repeated --brewfile is not supported"
          return 1
        fi
        RIG_PLAN_BREWFILE_SEEN=yes
        RIG_PLAN_BREWFILE=$2
        shift 2
        ;;
      --install-plan)
        if [ "$#" -lt 2 ]; then
          rig_print_error "--install-plan requires a value"
          return 1
        fi
        if [ "$RIG_PLAN_INSTALL_PLAN_SEEN" = "yes" ]; then
          rig_print_error "repeated --install-plan is not supported"
          return 1
        fi
        RIG_PLAN_INSTALL_PLAN_SEEN=yes
        RIG_PLAN_INSTALL_PLAN=$2
        shift 2
        ;;
      --auto-update)
        RIG_PLAN_AUTO_UPDATE=yes
        shift
        ;;
      --help|-h)
        printf '%s\n' "$help_text"
        if [ "$command_name" = "install" ]; then
          printf '%s\n' "$RIG_INSTALL_DESCRIPTION"
        fi
        RIG_PLAN_SHOWED_HELP=yes
        return 0
        ;;
      *)
        unknown_label=$1
        case "$command_name" in
          install)
            rig_print_error "unknown install argument: $unknown_label"
            ;;
          *)
            rig_print_error "unknown dry-run argument: $unknown_label"
            ;;
        esac
        return 1
        ;;
    esac
  done
  return 0
}

rig_reject_from_config_selection_flags() {
  if [ "$RIG_PLAN_FROM_CONFIG" != "yes" ]; then
    return 0
  fi
  if [ "$RIG_PLAN_SELECT" != "" ] || [ "$RIG_PLAN_DEFAULTS" != "" ] || [ "$RIG_PLAN_CATEGORY" != "" ] || [ "$RIG_PLAN_VERSION" != "" ]; then
    rig_print_error "--from-config cannot be combined with --select, --defaults, --category, or --version"
    return 1
  fi
  return 0
}

rig_plan_uses_interactive_selection() {
  if [ "$RIG_PLAN_FROM_CONFIG" = "yes" ]; then
    return 1
  fi
  if [ "$RIG_PLAN_WRITE_CONFIG_ONLY" = "yes" ]; then
    return 1
  fi
  if [ "$RIG_PLAN_SELECT_SEEN" = "yes" ] || [ "$RIG_PLAN_DEFAULTS_SEEN" = "yes" ] || [ "$RIG_PLAN_CATEGORY_SEEN" = "yes" ] || [ "$RIG_PLAN_VERSION_SEEN" = "yes" ]; then
    return 1
  fi
  if [ "$RIG_PLAN_BREWFILE_SEEN" = "yes" ] || [ "$RIG_PLAN_INSTALL_PLAN_SEEN" = "yes" ]; then
    return 1
  fi
  return 0
}

rig_resolve_plan_selections() {
  local version_map selected_tools selected_defaults
  version_map=
  if [ "$RIG_PLAN_VERSION" != "" ]; then
    if ! version_map=$(rig_parse_version_args "$RIG_PLAN_VERSION"); then
      return 1
    fi
  fi
  if ! version_map=$(rig_collect_inline_select_versions "$RIG_PLAN_SELECT" "$version_map"); then
    return 1
  fi
  RIG_PLAN_VERSION_MAP=$version_map
  if ! selected_tools=$(rig_collect_selected_tools "$RIG_PLAN_SELECT" "$RIG_PLAN_CATEGORY"); then
    return 1
  fi
  if ! selected_defaults=$(rig_collect_selected_defaults "$RIG_PLAN_DEFAULTS"); then
    return 1
  fi
  RIG_PLAN_SELECTED_TOOLS=$selected_tools
  RIG_PLAN_SELECTED_DEFAULTS=$selected_defaults
}

rig_apply_plan_path_overrides() {
  if [ "$RIG_PLAN_BREWFILE" != "" ]; then
    export RIG_BREWFILE="$RIG_PLAN_BREWFILE"
  fi
  if [ "$RIG_PLAN_INSTALL_PLAN" != "" ]; then
    export RIG_INSTALL_PLAN="$RIG_PLAN_INSTALL_PLAN"
  fi
}

rig_finish_install_apply() {
  rig_apply_install || return 1
  if [ "$RIG_PLAN_AUTO_UPDATE" = "yes" ]; then
    rig_setup_auto_update || return 1
  fi
}

rig_write_plan_config() {
  local brewfile_content install_plan_content defaults_content brewfile_path plan_path defaults_path
  rig_config_ensure_dir || return 1
  brewfile_path=$(rig_brewfile_path)
  plan_path=$(rig_install_plan_path)
  defaults_path=$(rig_macos_defaults_path)
  if [ "$RIG_PLAN_BREWFILE" != "" ]; then
    brewfile_path=$RIG_PLAN_BREWFILE
  fi
  if [ "$RIG_PLAN_INSTALL_PLAN" != "" ]; then
    plan_path=$RIG_PLAN_INSTALL_PLAN
  fi

  brewfile_content=$(rig_emit_brewfile_content "$RIG_PLAN_SELECTED_TOOLS")
  install_plan_content=$(rig_emit_install_plan_content "$RIG_PLAN_SELECTED_TOOLS" "$RIG_PLAN_VERSION_MAP")
  defaults_content=$(rig_emit_macos_defaults_script "$RIG_PLAN_SELECTED_DEFAULTS")
  if ! printf '%s\n' "$defaults_content" | rig_validate_generated_defaults_content; then
    return 1
  fi

  rig_config_write_atomic "$brewfile_path" "$brewfile_content" || return 1
  rig_config_write_atomic "$plan_path" "$install_plan_content" || return 1
  rig_config_write_atomic "$defaults_path" "$defaults_content" || return 1
  printf 'Wrote rig config to %s\n' "$(rig_config_dir)"
}

rig_count_shell_edits_from_plan_file() {
  local plan_file line strategy count id _package _version _label
  plan_file=$1
  count=0
  if [ ! -f "$plan_file" ]; then
    printf '0\n'
    return 0
  fi
  while IFS= read -r line || [ "$line" != "" ]; do
    case "$line" in
      ""|"id"$'\t'*)
        continue
        ;;
    esac
    IFS=$'\t' read -r id strategy _package _version _label < <(printf '%s\n' "$line")
    if rig_strategy_needs_shell_edit "$strategy"; then
      count=$((count + 1))
    fi
  done <"$plan_file"
  printf '%s\n' "$count"
}

rig_render_auto_update_preview() {
  printf '# Auto-update preview\n'
  printf 'Would tap domt4/tap\n'
  printf 'Would install homebrew-autoupdate\n'
  printf 'Would run: brew autoupdate start --upgrade --cleanup --greedy\n\n'
}

rig_count_preview_lines() {
  local value count line
  value=$1
  count=0
  while IFS= read -r line || [ "$line" != "" ]; do
    if [ "$line" = "" ]; then
      continue
    fi
    count=$((count + 1))
  done < <(printf '%s\n' "$value")
  printf '%s\n' "$count"
}

rig_count_brewfile_preview_selections() {
  local value count line
  value=$1
  count=0
  while IFS= read -r line || [ "$line" != "" ]; do
    case "$line" in
      ""|"tap "*)
        continue
        ;;
    esac
    count=$((count + 1))
  done < <(printf '%s\n' "$value")
  printf '%s\n' "$count"
}

rig_render_dry_run_summary() {
  local brewfile_count external_count defaults_count shell_edit_count
  brewfile_count=$1
  external_count=$2
  defaults_count=$3
  shell_edit_count=$4
  printf '# Summary\n'
  printf 'Homebrew-native packages: %s\n' "$brewfile_count"
  printf 'External installers: %s\n' "$external_count"
  printf 'macOS defaults: %s\n' "$defaults_count"
  printf 'Shell/profile edits: %s\n\n' "$shell_edit_count"
}

rig_render_dry_run_from_config() {
  local brewfile plan_file defaults_script brewfile_preview external_preview defaults_preview
  local shell_edit_count profile_path login_shell line id strategy package version label
  rig_require_macos || return 1
  rig_apply_plan_path_overrides
  if ! rig_config_exists; then
    rig_print_error "no rig config found under $(rig_config_dir)"
    return 1
  fi
  brewfile=$(rig_brewfile_path)
  plan_file=$(rig_install_plan_path)
  defaults_script=$(rig_macos_defaults_path)

  printf 'rig dry-run\n'
  printf 'No packages, config files, shell files, defaults, or LaunchAgents will be changed.\n\n'

  rig_homebrew_preflight dry-run "$RIG_PLAN_YES" no || return 1

  brewfile_preview=
  if [ -f "$brewfile" ] && grep -v '^[[:space:]]*#' "$brewfile" | grep -v '^[[:space:]]*$' >/dev/null 2>&1; then
    brewfile_preview=$(grep -v '^[[:space:]]*#' "$brewfile" | grep -v '^[[:space:]]*$' || true)
  fi
  external_preview=
  if [ -f "$plan_file" ]; then
    while IFS= read -r line || [ "$line" != "" ]; do
      case "$line" in
        ""|"id"$'\t'*)
          continue
          ;;
      esac
      IFS=$'\t' read -r id strategy package version label < <(printf '%s\n' "$line")
      external_preview="${external_preview}${id}	${package}	${version}	${label}
"
    done <"$plan_file"
  fi
  defaults_preview=
  if [ -f "$defaults_script" ] && [ -s "$defaults_script" ]; then
    defaults_preview=$(grep -v '^#!' "$defaults_script" | grep -v '^#' | grep -v '^[[:space:]]*$' | grep -v '^killall ' || true)
  fi
  shell_edit_count=$(rig_count_shell_edits_from_plan_file "$plan_file")

  rig_render_dry_run_summary \
    "$(rig_count_brewfile_preview_selections "$brewfile_preview")" \
    "$(rig_count_preview_lines "$external_preview")" \
    "$(rig_count_preview_lines "$defaults_preview")" \
    "$shell_edit_count"

  printf '# Brewfile preview\n'
  if [ "$brewfile_preview" != "" ]; then
    printf '%s\n' "$brewfile_preview"
  else
    printf 'No Homebrew-native packages in saved config.\n'
  fi
  printf '\n'

  printf '# External install plan preview\n'
  if [ "$external_preview" = "" ]; then
    printf 'No external installers in saved config.\n'
  else
    printf '%s' "$external_preview"
  fi
  printf '\n'

  printf '# macOS defaults preview\n'
  if [ "$defaults_preview" = "" ]; then
    printf 'No macOS defaults in saved config.\n'
  else
    printf '%s\n' "$defaults_preview"
  fi
  printf '\n'

  printf '# Shell/profile edits preview\n'
  if profile_path=$(rig_profile_path 2>/dev/null); then
    if [ "$shell_edit_count" -gt 0 ]; then
      printf 'Would add managed rig initialization block to %s.\n' "$profile_path"
    else
      printf 'No shell/profile edits in saved config.\n'
    fi
  else
    if login_shell=$(rig_login_shell 2>/dev/null); then
      printf 'Unsupported login shell: %s. rig would warn instead of editing shell files.\n' "$(basename "$login_shell")"
    else
      printf 'Unsupported login shell: unknown. rig would warn instead of editing shell files.\n'
    fi
  fi
  printf '\n'

  if [ "$RIG_PLAN_AUTO_UPDATE" = "yes" ]; then
    rig_render_auto_update_preview
  fi
}

rig_print_dry_run_intro() {
  printf 'rig dry-run\n'
  printf 'No packages, config files, shell files, defaults, or LaunchAgents will be changed.\n\n'
}

rig_render_dry_run_plan_sections() {
  local shell_edit_count profile_path login_shell
  local brewfile_preview external_preview defaults_preview
  local brewfile_count external_count defaults_count

  brewfile_preview=$(rig_emit_brewfile_content "$RIG_PLAN_SELECTED_TOOLS")
  external_preview=$(rig_emit_install_plan_preview "$RIG_PLAN_SELECTED_TOOLS" "$RIG_PLAN_VERSION_MAP")
  defaults_preview=$(rig_emit_macos_defaults_preview "$RIG_PLAN_SELECTED_DEFAULTS")
  shell_edit_count=$(rig_count_shell_edits_needed "$RIG_PLAN_SELECTED_TOOLS")
  brewfile_count=$(rig_count_homebrew_selected "$RIG_PLAN_SELECTED_TOOLS")
  external_count=$(rig_count_external_selected "$RIG_PLAN_SELECTED_TOOLS")
  defaults_count=$(rig_count_lines "$RIG_PLAN_SELECTED_DEFAULTS")

  rig_render_dry_run_summary "$brewfile_count" "$external_count" "$defaults_count" "$shell_edit_count"

  printf '# Brewfile preview\n'
  if [ "$brewfile_preview" = "" ]; then
    printf 'No Homebrew-native packages selected.\n'
  else
    printf '%s\n' "$brewfile_preview"
  fi
  printf '\n'

  printf '# External install plan preview\n'
  if [ "$external_preview" = "" ]; then
    printf 'No external installers selected.\n'
  else
    printf '%s\n' "$external_preview"
  fi
  printf '\n'

  printf '# macOS defaults preview\n'
  if [ "$defaults_preview" = "" ]; then
    printf 'No macOS defaults selected.\n'
  else
    printf '%s\n' "$defaults_preview"
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
  printf '\n'

  if [ "$RIG_PLAN_AUTO_UPDATE" = "yes" ]; then
    rig_render_auto_update_preview
  fi
}

rig_render_dry_run_body() {
  rig_print_dry_run_intro
  rig_homebrew_preflight dry-run "$RIG_PLAN_YES" no || return 1
  rig_render_dry_run_plan_sections
}

rig_render_dry_run() {
  if ! rig_parse_plan_args dry-run "$@"; then
    return 1
  fi
  if [ "$RIG_PLAN_SHOWED_HELP" = "yes" ]; then
    return 0
  fi

  rig_prepare_plan_selections || return 1
  rig_render_dry_run_body
}

rig_run_install() {
  if ! rig_parse_plan_args install "$@"; then
    return 1
  fi
  if [ "$RIG_PLAN_SHOWED_HELP" = "yes" ]; then
    return 0
  fi

  if ! rig_reject_from_config_selection_flags; then
    return 1
  fi

  if [ "$RIG_PLAN_DRY_RUN" = "yes" ]; then
    if [ "$RIG_PLAN_FROM_CONFIG" = "yes" ]; then
      rig_render_dry_run_from_config || return 1
    else
      if rig_plan_uses_interactive_selection; then
        rig_require_macos || return 1
        rig_validate_catalogs || return 1
        rig_require_interactive_terminal || return 1
        rig_print_dry_run_intro
        rig_homebrew_preflight dry-run "$RIG_PLAN_YES" yes || return 1
        rig_run_interactive_selection || return 1
        rig_render_dry_run_plan_sections
      else
        rig_prepare_plan_selections || return 1
        rig_render_dry_run_body
      fi
    fi
    return 0
  fi

  rig_require_macos || return 1
  rig_validate_catalogs || return 1

  if [ "$RIG_PLAN_FROM_CONFIG" = "yes" ]; then
    rig_apply_plan_path_overrides
    if ! rig_config_exists; then
      rig_print_error "no rig config found under $(rig_config_dir)"
      return 1
    fi
    if [ "$RIG_PLAN_WRITE_CONFIG_ONLY" = "yes" ]; then
      rig_print_error "--from-config cannot be combined with --write-config-only"
      return 1
    fi
    rig_homebrew_preflight install "$RIG_PLAN_YES" no || return 1
    rig_finish_install_apply || return 1
    return 0
  fi

  if rig_plan_uses_interactive_selection; then
    rig_require_interactive_terminal || return 1
    rig_homebrew_preflight install "$RIG_PLAN_YES" yes || return 1
    rig_run_interactive_selection || return 1
  else
    rig_prepare_plan_selections || return 1
    if [ "$RIG_PLAN_WRITE_CONFIG_ONLY" != "yes" ]; then
      rig_homebrew_preflight install "$RIG_PLAN_YES" no || return 1
    fi
  fi

  rig_apply_plan_path_overrides
  rig_write_plan_config || return 1

  if [ "$RIG_PLAN_WRITE_CONFIG_ONLY" = "yes" ]; then
    return 0
  fi

  rig_finish_install_apply || return 1
}
