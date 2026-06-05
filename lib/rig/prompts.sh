#!/bin/bash

rig_prompt_yes_no() {
  local prompt default reply
  prompt=$1
  default=${2:-no}
  if rig_prompt_use_gum; then
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
  if [ "$default" = "yes" ]; then
    printf '%s [Y/n]: ' "$prompt" >&2
  else
    printf '%s [y/N]: ' "$prompt" >&2
  fi
  if ! IFS= read -r reply; then
    rig_prompt_finish_input_line
    return 1
  fi
  rig_prompt_finish_input_line
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

rig_prompt_use_gum() {
  rig_command_exists gum && [ -t 0 ]
}

rig_prompt_finish_input_line() {
  if [ ! -t 0 ]; then
    printf '\n' >&2
  fi
}

rig_prompt_can_read() {
  if [ "${RIG_ALLOW_NON_TTY_PROMPTS:-}" = "yes" ]; then
    return 0
  fi
  [ -t 0 ]
}

rig_require_interactive_terminal() {
  if rig_prompt_can_read; then
    return 0
  fi
  rig_print_error "interactive selection requires a terminal; use --select/--defaults flags or run rig from an interactive shell"
  return 1
}

rig_category_label() {
  case "$1" in
    ide) printf 'IDEs and editors\n' ;;
    terminal) printf 'Terminals\n' ;;
    browser) printf 'Browsers\n' ;;
    devops) printf 'DevOps CLIs\n' ;;
    containers) printf 'Containers\n' ;;
    runtime) printf 'JavaScript runtimes\n' ;;
    infra) printf 'Infrastructure tools\n' ;;
    kubernetes) printf 'Kubernetes tools\n' ;;
    ai) printf 'AI tools\n' ;;
    communication) printf 'Communication apps\n' ;;
    productivity) printf 'Productivity and security\n' ;;
    fonts) printf 'Fonts\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

rig_prompt_screen_clear() {
  if [ -t 0 ] && [ "${RIG_PROMPT_NO_CLEAR:-}" != "yes" ]; then
    printf '\033[H\033[2J' >&2
  fi
}

rig_prompt_color_enabled() {
  if [ ! -t 2 ]; then
    return 1
  fi
  if [ "${NO_COLOR:-}" != "" ]; then
    return 1
  fi
  if [ "${TERM:-}" = "dumb" ]; then
    return 1
  fi
  return 0
}

rig_prompt_style() {
  local code value
  code=$1
  value=$2
  if rig_prompt_color_enabled; then
    printf '\033[%sm%s\033[0m' "$code" "$value"
  else
    printf '%s' "$value"
  fi
}

rig_prompt_dim() {
  rig_prompt_style 2 "$1"
}

rig_prompt_bold() {
  rig_prompt_style 1 "$1"
}

rig_prompt_green() {
  rig_prompt_style 32 "$1"
}

rig_prompt_sanitize_text() {
  LC_ALL=C printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037\177'
}

rig_count_lines() {
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

rig_prompt_header() {
  local title selected_count header
  title=$1
  selected_count=${RIG_PROMPT_SELECTED_COUNT:-0}
  rig_prompt_screen_clear
  header='rig setup'
  if [ "${RIG_PLAN_DRY_RUN:-no}" = "yes" ]; then
    header="${header} dry-run"
  fi
  if [ "${RIG_PROMPT_STEP:-}" != "" ] && [ "${RIG_PROMPT_TOTAL:-}" != "" ]; then
    header="${header} | ${RIG_PROMPT_STEP}/${RIG_PROMPT_TOTAL} ${title}"
  elif [ "${RIG_PROMPT_STEP:-}" != "" ]; then
    header="${header} | category ${RIG_PROMPT_STEP} ${title}"
  else
    header="${header} | ${title}"
  fi
  header="${header} | selected ${selected_count}"
  printf '%s\n' "$(rig_prompt_bold "$header")" >&2
  printf '\n' >&2
}

rig_prompt_label_to_id() {
  local items label item_id item_label safe_label
  items=$1
  label=$2
  while IFS='|' read -r item_id item_label _item_description; do
    if [ "$item_id" = "" ]; then
      continue
    fi
    safe_label=$(rig_prompt_sanitize_text "$item_label")
    if [ "$safe_label" = "$label" ]; then
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

rig_prompt_item_id_at() {
  local items wanted index item_id _item_label _item_description
  items=$1
  wanted=$2
  index=1
  while IFS='|' read -r item_id _item_label _item_description; do
    if [ "$item_id" = "" ]; then
      continue
    fi
    if [ "$index" -eq "$wanted" ]; then
      printf '%s\n' "$item_id"
      return 0
    fi
    index=$((index + 1))
  done < <(printf '%s\n' "$items")
  return 1
}

rig_prompt_selection_contains() {
  local selected wanted item
  selected=$1
  wanted=$2
  while IFS= read -r item || [ "$item" != "" ]; do
    if [ "$item" = "$wanted" ]; then
      return 0
    fi
  done < <(printf '%s\n' "$selected")
  return 1
}

rig_prompt_toggle_selected() {
  local selected wanted output item found
  selected=$1
  wanted=$2
  output='
'
  found=no
  while IFS= read -r item || [ "$item" != "" ]; do
    if [ "$item" = "" ]; then
      continue
    fi
    if [ "$item" = "$wanted" ]; then
      found=yes
      continue
    fi
    if ! rig_prompt_selection_contains "$output" "$item"; then
      output="${output}${item}
"
    fi
  done < <(printf '%s\n' "$selected")
  if [ "$found" = "no" ]; then
    output="${output}${wanted}
"
  fi
  printf '%s' "$output"
}

rig_prompt_select_all_items() {
  local items selected item_id _item_label _item_description
  items=$1
  selected='
'
  while IFS='|' read -r item_id _item_label _item_description; do
    if [ "$item_id" = "" ]; then
      continue
    fi
    selected="${selected}${item_id}
"
  done < <(printf '%s\n' "$items")
  printf '%s' "$selected"
}

rig_prompt_print_selected_items() {
  local items selected item_id _item_label _item_description
  items=$1
  selected=$2
  while IFS='|' read -r item_id _item_label _item_description; do
    if [ "$item_id" = "" ]; then
      continue
    fi
    if rig_prompt_selection_contains "$selected" "$item_id"; then
      printf '%s\n' "$item_id"
    fi
  done < <(printf '%s\n' "$items")
}

rig_prompt_render_multi_select_rows() {
  local items selected cursor row_mode index item_id item_label item_description pointer mark line description
  items=$1
  selected=$2
  cursor=$3
  row_mode=$4
  index=1
  while IFS='|' read -r item_id item_label item_description; do
    if [ "$item_id" = "" ]; then
      continue
    fi
    item_label=$(rig_prompt_sanitize_text "$item_label")
    item_description=$(rig_prompt_sanitize_text "$item_description")
    pointer=' '
    if [ "$index" -eq "$cursor" ]; then
      pointer='>'
    fi
    mark=' '
    if rig_prompt_selection_contains "$selected" "$item_id"; then
      mark=$(rig_prompt_green x)
    fi
    description=$item_description
    if [ "$index" -ne "$cursor" ]; then
      description=$(rig_prompt_dim "$item_description")
    fi
    case "$row_mode" in
      defaults)
        line=$(printf '%s [%s] %-24s %-30s %s' "$pointer" "$mark" "$item_label" "$item_id" "$description")
        ;;
      *)
        line=$(printf '%s [%s] %-24s %-16s %s' "$pointer" "$mark" "$item_label" "$item_id" "$description")
        ;;
    esac
    if [ "$index" -eq "$cursor" ]; then
      line=$(rig_prompt_bold "$line")
    fi
    printf '%s\n' "$line" >&2
    index=$((index + 1))
  done < <(printf '%s\n' "$items")
}

rig_prompt_read_key() {
  local key rest escape
  RIG_PROMPT_KEY=
  if ! IFS= read -r -s -n 1 key; then
    return 1
  fi
  escape=$(printf '\033')
  if [ "$key" = "$escape" ]; then
    rest=
    IFS= read -r -s -n 2 rest || true
    case "$rest" in
      "[A") RIG_PROMPT_KEY=up ;;
      "[B") RIG_PROMPT_KEY=down ;;
      *) RIG_PROMPT_KEY=other ;;
    esac
    return 0
  fi
  case "$key" in
    "") RIG_PROMPT_KEY=enter ;;
    " ") RIG_PROMPT_KEY=space ;;
    a|A) RIG_PROMPT_KEY=all ;;
    n|N) RIG_PROMPT_KEY=none ;;
    q|Q) RIG_PROMPT_KEY=quit ;;
    j|J) RIG_PROMPT_KEY=down ;;
    k|K) RIG_PROMPT_KEY=up ;;
    *) RIG_PROMPT_KEY=other ;;
  esac
  return 0
}

rig_prompt_multi_select() {
  local title items row_mode item_count cursor selected key current_id base_selected_count current_selected_count
  title=$1
  items=$2
  row_mode=$3
  item_count=$(rig_count_lines "$items")
  if [ "$item_count" -eq 0 ]; then
    return 0
  fi

  cursor=1
  base_selected_count=${RIG_PROMPT_SELECTED_COUNT:-0}
  selected='
'
  while :; do
    current_selected_count=$(rig_count_lines "$selected")
    RIG_PROMPT_SELECTED_COUNT=$((base_selected_count + current_selected_count))
    rig_prompt_header "$title"
    case "$row_mode" in
      defaults)
        printf 'Choose macOS preferences.\n\n' >&2
        ;;
      *)
        printf 'Choose tools for this category.\n\n' >&2
        ;;
    esac
    rig_prompt_render_multi_select_rows "$items" "$selected" "$cursor" "$row_mode"
    printf '\nUp/Down move  Space toggle  Enter continue  a all  n clear  q skip\n' >&2

    if ! rig_prompt_read_key; then
      break
    fi
    key=$RIG_PROMPT_KEY
    case "$key" in
      up)
        if [ "$cursor" -le 1 ]; then
          cursor=$item_count
        else
          cursor=$((cursor - 1))
        fi
        ;;
      down)
        if [ "$cursor" -ge "$item_count" ]; then
          cursor=1
        else
          cursor=$((cursor + 1))
        fi
        ;;
      space)
        current_id=$(rig_prompt_item_id_at "$items" "$cursor")
        selected=$(rig_prompt_toggle_selected "$selected" "$current_id")
        ;;
      all)
        selected=$(rig_prompt_select_all_items "$items")
        ;;
      none)
        selected='
'
        ;;
      enter)
        break
        ;;
      quit)
        selected='
'
        break
        ;;
    esac
  done

  printf '\n' >&2
  rig_prompt_print_selected_items "$items" "$selected"
}

rig_prompt_tools_for_category() {
  local category category_label items item_count choice
  local _category id label _kind _package _default_flag description _version_strategy _versions _notes
  local safe_tool_label safe_tool_description
  category=$1
  category_label=$(rig_category_label "$category")
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

  if rig_prompt_use_gum; then
    choice=$(printf '%s\n' "$items" | while IFS='|' read -r tool_id tool_label tool_description; do
      if [ "$tool_id" = "" ]; then
        continue
      fi
      safe_tool_label=$(rig_prompt_sanitize_text "$tool_label")
      safe_tool_description=$(rig_prompt_sanitize_text "$tool_description")
      printf '%s - %s\n' "$safe_tool_label" "$safe_tool_description"
    done | gum choose --no-limit --header "Select tools in $category (space to toggle)" || true)
    if [ "$choice" = "" ]; then
      return 0
    fi
    rig_prompt_ids_from_labels "$items" "$choice"
    return 0
  fi

  rig_prompt_multi_select "$category_label" "$items" tools
}

rig_prompt_version() {
  local tool_id versions_csv versions version choice
  tool_id=$1
  versions_csv=$2
  versions=$(printf '%s' "$versions_csv" | tr ',' '
')
  if rig_prompt_use_gum; then
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
  rig_prompt_finish_input_line
  if [ "$choice" = "" ]; then
    choice=latest
  fi
  if ! rig_validate_tool_version "$tool_id" "$choice"; then
    return 1
  fi
  printf '%s\n' "$choice"
}

rig_prompt_defaults() {
  local items selected default_id safe_default_label safe_default_description
  items=
  while IFS="$RIG_TSV_DELIMITER" read -r id label description _domain _key _value_type _value _restart; do
    items="${items}${id}|${label}|${description}
"
  done < <(rig_each_default)
  if rig_prompt_use_gum; then
    selected=$(printf '%s\n' "$items" | while IFS='|' read -r default_id default_label default_description; do
      if [ "$default_id" = "" ]; then
        continue
      fi
      safe_default_label=$(rig_prompt_sanitize_text "$default_label")
      safe_default_description=$(rig_prompt_sanitize_text "$default_description")
      printf '%s - %s\n' "$safe_default_label" "$safe_default_description"
    done | gum choose --no-limit --header "Optional macOS preferences" || true)
    if [ "$selected" = "" ]; then
      return 0
    fi
    rig_prompt_ids_from_labels "$items" "$selected"
    return 0
  fi

  rig_prompt_multi_select "macOS preferences" "$items" defaults
}

rig_prompt_append_label() {
  local current label
  current=$1
  label=$(rig_prompt_sanitize_text "$2")
  if [ "$current" = "" ]; then
    printf '%s' "$label"
  else
    printf '%s, %s' "$current" "$label"
  fi
}

rig_prompt_print_review_tools() {
  local selected_tools category labels selected_id row row_category _id label _kind _package _default_flag _description _version_strategy _versions _notes printed category_label
  selected_tools=$1
  printed=no
  printf 'Tools\n' >&2
  while IFS= read -r category || [ "$category" != "" ]; do
    if [ "$category" = "" ]; then
      continue
    fi
    labels=
    while IFS= read -r selected_id || [ "$selected_id" != "" ]; do
      if [ "$selected_id" = "" ]; then
        continue
      fi
      row=$(rig_lookup_tool "$selected_id")
      IFS="$RIG_TSV_DELIMITER" read -r row_category _id label _kind _package _default_flag _description _version_strategy _versions _notes < <(printf '%s\n' "$row")
      if [ "$row_category" = "$category" ]; then
        labels=$(rig_prompt_append_label "$labels" "$label")
      fi
    done < <(printf '%s\n' "$selected_tools")
    if [ "$labels" != "" ]; then
      category_label=$(rig_prompt_sanitize_text "$(rig_category_label "$category")")
      printf '  %s: %s\n' "$category_label" "$labels" >&2
      printed=yes
    fi
  done < <(rig_each_category)
  if [ "$printed" = "no" ]; then
    printf '  No tools selected.\n' >&2
  fi
  printf '\n' >&2
}

rig_prompt_print_review_defaults() {
  local selected_defaults selected_id row _id label _description _domain _key _value_type _value _restart printed
  selected_defaults=$1
  printed=no
  printf 'macOS preferences\n' >&2
  while IFS= read -r selected_id || [ "$selected_id" != "" ]; do
    if [ "$selected_id" = "" ]; then
      continue
    fi
    row=$(rig_lookup_default "$selected_id")
    IFS="$RIG_TSV_DELIMITER" read -r _id label _description _domain _key _value_type _value _restart < <(printf '%s\n' "$row")
    label=$(rig_prompt_sanitize_text "$label")
    printf '  %s\n' "$label" >&2
    printed=yes
  done < <(printf '%s\n' "$selected_defaults")
  if [ "$printed" = "no" ]; then
    printf '  No macOS preferences selected.\n' >&2
  fi
  printf '\n' >&2
}

rig_prompt_review_selection() {
  rig_prompt_screen_clear
  printf '%s\n\n' "$(rig_prompt_bold "Review selection")" >&2
  rig_prompt_print_review_tools "$RIG_PLAN_SELECTED_TOOLS"
  rig_prompt_print_review_defaults "$RIG_PLAN_SELECTED_DEFAULTS"
  printf 'Homebrew auto-update: %s\n\n' "$RIG_PLAN_AUTO_UPDATE" >&2
  if [ "${RIG_PLAN_DRY_RUN:-no}" = "yes" ]; then
    rig_prompt_yes_no "Continue to dry-run preview?" yes
    return $?
  fi
  if rig_prompt_yes_no "Continue with install?" no; then
    return 0
  fi
  rig_print_error "setup cancelled"
  return 1
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
  local category selected_tools selected_defaults version_map tool_id row version _versions category_index category_total
  local _category _id _label _kind _package _default_flag _description _version_strategy _notes auto_update
  RIG_PLAN_SELECTED_TOOLS=
  RIG_PLAN_SELECTED_DEFAULTS=
  RIG_PLAN_VERSION_MAP=
  rig_require_interactive_terminal || return 1
  selected_tools=
  version_map=
  category_index=0
  category_total=$(rig_count_lines "$(rig_each_category)")
  RIG_PROMPT_TOTAL=$category_total
  while IFS= read -r category <&4 || [ "$category" != "" ]; do
    if [ "$category" = "" ]; then
      continue
    fi
    category_index=$((category_index + 1))
    RIG_PROMPT_STEP=$category_index
    RIG_PROMPT_SELECTED_COUNT=$(rig_count_lines "$selected_tools")
    while IFS= read -r tool_id <&3 || [ "$tool_id" != "" ]; do
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
    done 3< <(rig_prompt_tools_for_category "$category")
  done 4< <(rig_each_category)

  RIG_PROMPT_STEP=
  RIG_PROMPT_TOTAL=
  RIG_PROMPT_SELECTED_COUNT=$(rig_count_lines "$selected_tools")
  selected_defaults=$(rig_prompt_defaults)
  RIG_PROMPT_STEP=
  RIG_PROMPT_SELECTED_COUNT=$(rig_count_lines "$selected_tools")
  if [ "$RIG_PLAN_AUTO_UPDATE" = "yes" ]; then
    auto_update=yes
  else
    auto_update=$(rig_prompt_auto_update)
  fi

  # Set for rig_install_command caller.
  # shellcheck disable=SC2034
  RIG_PLAN_SELECTED_TOOLS=$selected_tools
  # shellcheck disable=SC2034
  RIG_PLAN_SELECTED_DEFAULTS=$selected_defaults
  # shellcheck disable=SC2034
  RIG_PLAN_VERSION_MAP=$version_map
  # shellcheck disable=SC2034
  RIG_PLAN_AUTO_UPDATE=$auto_update
  rig_prompt_review_selection || return 1
}
