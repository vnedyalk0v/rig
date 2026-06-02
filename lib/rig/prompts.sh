#!/bin/bash

rig_prompt_yes_no() {
  local prompt default reply
  prompt=$1
  default=${2:-no}
  if rig_command_exists gum; then
    case "$default" in
      yes)
        gum confirm "$prompt" --default=true
        return $?
        ;;
      *)
        gum confirm "$prompt" --default=false
        return $?
        ;;
    esac
  fi
  printf '%s [y/N]: ' "$prompt" >&2
  IFS= read -r reply
  case "$reply" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      if [ "$default" = "yes" ] && [ "$reply" = "" ]; then
        return 0
      fi
      return 1
      ;;
  esac
}

rig_prompt_label_to_id() {
  local items label item_id item_label
  items=$1
  label=$2
  while IFS='|' read -r item_id item_label _item_description; do
    if [ "$item_id" = "" ]; then
      continue
    fi
    if [ "$item_label" = "$label" ]; then
      printf '%s\n' "$item_id"
      return 0
    fi
  done < <(printf '%s\n' "$items")
  return 1
}

rig_prompt_ids_from_labels() {
  local items labels selected_line label
  items=$1
  labels=$2
  printf '%s\n' "$labels" | while IFS= read -r selected_line || [ "$selected_line" != "" ]; do
    label=${selected_line%% - *}
    rig_prompt_label_to_id "$items" "$label"
  done
}

rig_prompt_tools_for_category() {
  local category items item_count index choice selected token
  local _category id label _kind _package _default_flag description _version_strategy _versions _notes
  category=$1
  items=
  item_count=0
  while IFS="$RIG_TSV_DELIMITER" read -r _category id label _kind _package _default_flag description _version_strategy _versions _notes; do
    if [ "$_category" != "$category" ]; then
      continue
    fi
    item_count=$((item_count + 1))
    items="${items}${id}|${label}|${description}
"
  done < <(rig_each_tool)
  if [ "$item_count" -eq 0 ]; then
    return 0
  fi

  if rig_command_exists gum; then
    choice=$(printf '%s\n' "$items" | while IFS='|' read -r tool_id tool_label tool_description; do
      if [ "$tool_id" = "" ]; then
        continue
      fi
      printf '%s - %s\n' "$tool_label" "$tool_description"
    done | gum choose --no-limit --header "Select tools in $category (space to toggle)" || true)
    if [ "$choice" = "" ]; then
      return 0
    fi
    rig_prompt_ids_from_labels "$items" "$choice"
    return 0
  fi

  printf 'Category: %s\n' "$category" >&2
  index=1
  printf '%s\n' "$items" | while IFS='|' read -r tool_id tool_label tool_description; do
    if [ "$tool_id" = "" ]; then
      continue
    fi
    printf '  %s) %s - %s\n' "$index" "$tool_label" "$tool_description" >&2
    index=$((index + 1))
  done
  printf 'Enter numbers or ids (comma/space separated, blank to skip): ' >&2
  IFS= read -r choice
  if [ "$choice" = "" ]; then
    return 0
  fi
  while IFS= read -r token || [ "$token" != "" ]; do
    if [ "$token" = "" ]; then
      continue
    fi
    case "$token" in
      *[!0-9]*)
        if rig_lookup_tool "$token" >/dev/null 2>&1; then
          printf '%s\n' "$token"
        fi
        ;;
      *)
        index=1
        printf '%s\n' "$items" | while IFS='|' read -r tool_id tool_label _tool_description; do
          if [ "$tool_id" = "" ]; then
            continue
          fi
          if [ "$index" -eq "$token" ]; then
            printf '%s\n' "$tool_id"
          fi
          index=$((index + 1))
        done
        ;;
    esac
  done < <(printf '%s\n' "$choice" | tr ', ' '
')
}

rig_prompt_version() {
  local tool_id versions_csv versions version choice
  tool_id=$1
  versions_csv=$2
  versions=$(printf '%s' "$versions_csv" | tr ',' '
')
  if rig_command_exists gum; then
    choice=$(printf '%s\n' "$versions" | gum choose --header "Version for $tool_id" || true)
    if [ "$choice" != "" ]; then
      if ! rig_validate_tool_version "$tool_id" "$choice"; then
        return 1
      fi
      printf '%s\n' "$choice"
    fi
    return 0
  fi
  printf 'Choose version for %s:\n' "$tool_id" >&2
  while IFS= read -r version || [ "$version" != "" ]; do
    if [ "$version" = "" ]; then
      continue
    fi
    printf '  - %s\n' "$version" >&2
  done < <(rig_join_csv_as_lines "$versions_csv")
  printf 'Version [latest]: ' >&2
  IFS= read -r choice
  if [ "$choice" = "" ]; then
    choice=latest
  fi
  if ! rig_validate_tool_version "$tool_id" "$choice"; then
    return 1
  fi
  printf '%s\n' "$choice"
}

rig_prompt_defaults() {
  local items selected
  items=
  while IFS="$RIG_TSV_DELIMITER" read -r id label description _command _restart; do
    items="${items}${id}|${label}|${description}
"
  done < <(rig_each_default)
  if rig_command_exists gum; then
    selected=$(printf '%s\n' "$items" | while IFS='|' read -r default_id default_label default_description; do
      if [ "$default_id" = "" ]; then
        continue
      fi
      printf '%s - %s\n' "$default_label" "$default_description"
    done | gum choose --no-limit --header "Optional macOS preferences" || true)
    if [ "$selected" = "" ]; then
      return 0
    fi
    rig_prompt_ids_from_labels "$items" "$selected"
    return 0
  fi

  printf 'Optional macOS preferences (enter ids comma-separated, blank to skip):\n' >&2
  printf '%s\n' "$items" | while IFS='|' read -r default_id default_label default_description; do
    if [ "$default_id" = "" ]; then
      continue
    fi
    printf '  %s - %s\n' "$default_id" "$default_description" >&2
  done
  printf 'Defaults: ' >&2
  IFS= read -r selected
  if [ "$selected" = "" ]; then
    return 0
  fi
  rig_join_csv_as_lines "$selected"
}

rig_prompt_auto_update() {
  if rig_prompt_yes_no "Enable automatic Homebrew updates? (default: no)" no; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

rig_each_category() {
  local seen category _id _label _kind _package _default_flag _description _version_strategy _versions _notes
  seen='
'
  while IFS="$RIG_TSV_DELIMITER" read -r category _id _label _kind _package _default_flag _description _version_strategy _versions _notes; do
    if rig_seen_contains "$seen" "$category"; then
      continue
    fi
    printf '%s\n' "$category"
    seen="${seen}${category}
"
  done < <(rig_each_tool)
}

rig_run_interactive_selection() {
  local category selected_tools selected_defaults version_map tool_id row version _versions
  local _category _id _label _kind _package _default_flag _description _version_strategy _notes auto_update
  rig_reset_plan_globals
  selected_tools=
  version_map=
  while IFS= read -r category || [ "$category" != "" ]; do
    if [ "$category" = "" ]; then
      continue
    fi
    while IFS= read -r tool_id || [ "$tool_id" != "" ]; do
      if [ "$tool_id" = "" ]; then
        continue
      fi
      selected_tools="${selected_tools}${tool_id}
"
      row=$(rig_lookup_tool "$tool_id")
      IFS="$RIG_TSV_DELIMITER" read -r _category _id _label _kind _package _default_flag _description _version_strategy _versions _notes < <(printf '%s\n' "$row")
      if [ "$_versions" != "" ]; then
        if ! version=$(rig_prompt_version "$tool_id" "$_versions"); then
          return 1
        fi
        if [ "$version" != "" ]; then
          version_map=$(rig_version_map_set "$version_map" "$tool_id" "$version")
        fi
      fi
    done < <(rig_prompt_tools_for_category "$category")
  done < <(rig_each_category)

  selected_defaults=$(rig_prompt_defaults)
  auto_update=$(rig_prompt_auto_update)

  # Set for rig_install_command caller.
  # shellcheck disable=SC2034
  RIG_PLAN_SELECTED_TOOLS=$selected_tools
  # shellcheck disable=SC2034
  RIG_PLAN_SELECTED_DEFAULTS=$selected_defaults
  # shellcheck disable=SC2034
  RIG_PLAN_VERSION_MAP=$version_map
  if [ "$auto_update" = "yes" ]; then
    # shellcheck disable=SC2034
    RIG_PLAN_AUTO_UPDATE=yes
  fi
}
