#!/bin/bash

RIG_TSV_DELIMITER=$(printf '\034')

rig_tools_catalog_path() {
  if [ "${RIG_TOOLS_CATALOG:-}" != "" ]; then
    printf '%s\n' "$RIG_TOOLS_CATALOG"
  else
    printf '%s\n' "$RIG_ROOT/catalog/tools.tsv"
  fi
}

rig_defaults_catalog_path() {
  if [ "${RIG_DEFAULTS_CATALOG:-}" != "" ]; then
    printf '%s\n' "$RIG_DEFAULTS_CATALOG"
  else
    printf '%s\n' "$RIG_ROOT/catalog/macos-defaults.tsv"
  fi
}

rig_field_count() {
  awk -F '\t' '{ print NF; exit }' <<EOF
$1
EOF
}

rig_tsv_to_record() {
  awk -F '\t' -v sep="$RIG_TSV_DELIMITER" '{
    for (i = 1; i <= NF; i++) {
      printf "%s%s", $i, (i < NF ? sep : ORS)
    }
  }' <<EOF
$1
EOF
}

rig_validate_id() {
  case "$1" in
    ""|*[!A-Za-z0-9._-]*)
      return 1
      ;;
  esac
  return 0
}

rig_validate_tool_kind() {
  case "$1" in
    formula|cask|tap-formula|external|version-manager|mas|vscode)
      return 0
      ;;
  esac
  return 1
}

rig_validate_version_strategy() {
  case "$1" in
    homebrew-latest|homebrew-channel|homebrew-or-vendor|nvm|tenv|bun-installer|npm-or-vendor|latest-only)
      return 0
      ;;
  esac
  return 1
}

rig_validate_default_flag() {
  case "$1" in
    yes|no)
      return 0
      ;;
  esac
  return 1
}

rig_record_field() {
  local record index
  record=$1
  index=$2
  printf '%s' "$record" | cut -d "$RIG_TSV_DELIMITER" -f "$index"
}

rig_validate_catalog() {
  local catalog_path noun expected_header expected_fields id_field row_validator
  local line_no seen_ids row_count line field_count record id
  catalog_path=$1
  noun=$2
  expected_header=$3
  expected_fields=$4
  id_field=$5
  row_validator=$6

  if [ ! -f "$catalog_path" ]; then
    rig_print_error "$noun catalog not found: $catalog_path"
    return 1
  fi

  line_no=0
  seen_ids='
'
  row_count=0

  # row_validator only reads its $record argument (a heredoc), never the catalog file.
  # shellcheck disable=SC2094
  while IFS= read -r line || [ "$line" != "" ]; do
    line_no=$((line_no + 1))
    if [ "$line_no" -eq 1 ]; then
      if [ "$line" != "$expected_header" ]; then
        rig_print_error "$catalog_path:1: invalid $noun catalog header"
        return 1
      fi
      continue
    fi

    if [ "$line" = "" ]; then
      continue
    fi

    field_count=$(rig_field_count "$line")
    if [ "$field_count" != "$expected_fields" ]; then
      rig_print_error "$catalog_path:$line_no: expected $expected_fields tab-separated fields, got $field_count"
      return 1
    fi

    record=$(rig_tsv_to_record "$line")
    id=$(rig_record_field "$record" "$id_field")
    if ! rig_validate_id "$id"; then
      rig_print_error "$catalog_path:$line_no: invalid id: $id"
      return 1
    fi
    case "$seen_ids" in
      *"
$id
"*)
        rig_print_error "$catalog_path:$line_no: duplicate id: $id"
        return 1
        ;;
    esac
    seen_ids="${seen_ids}${id}
"

    "$row_validator" "$catalog_path" "$line_no" "$record" || return 1
    row_count=$((row_count + 1))
  done <"$catalog_path"

  if [ "$row_count" -eq 0 ]; then
    rig_print_error "$catalog_path: catalog must contain at least one item"
    return 1
  fi

  return 0
}

rig_validate_tools_row() {
  local catalog_path line_no record
  local category id label kind package default_flag description version_strategy _versions _notes
  catalog_path=$1
  line_no=$2
  record=$3
  IFS="$RIG_TSV_DELIMITER" read -r category id label kind package default_flag description version_strategy _versions _notes <<EOF
$record
EOF

  if ! rig_validate_id "$category"; then
    rig_print_error "$catalog_path:$line_no: invalid category: $category"
    return 1
  fi
  if [ "$label" = "" ]; then
    rig_print_error "$catalog_path:$line_no: label is required"
    return 1
  fi
  if ! rig_validate_tool_kind "$kind"; then
    rig_print_error "$catalog_path:$line_no: invalid kind: $kind"
    return 1
  fi
  if [ "$package" = "" ]; then
    rig_print_error "$catalog_path:$line_no: package is required"
    return 1
  fi
  if [ "$kind" = "mas" ]; then
    case "$package" in
      ""|*[!0-9]*)
        rig_print_error "$catalog_path:$line_no: invalid mas id: $package"
        return 1
        ;;
    esac
  fi
  if ! rig_validate_default_flag "$default_flag"; then
    rig_print_error "$catalog_path:$line_no: invalid default flag: $default_flag"
    return 1
  fi
  if [ "$description" = "" ]; then
    rig_print_error "$catalog_path:$line_no: description is required"
    return 1
  fi
  if ! rig_validate_version_strategy "$version_strategy"; then
    rig_print_error "$catalog_path:$line_no: invalid version strategy: $version_strategy"
    return 1
  fi
  return 0
}

rig_validate_defaults_row() {
  local catalog_path line_no record
  local id label description command_text _restart_hint
  catalog_path=$1
  line_no=$2
  record=$3
  IFS="$RIG_TSV_DELIMITER" read -r id label description command_text _restart_hint <<EOF
$record
EOF

  if [ "$label" = "" ]; then
    rig_print_error "$catalog_path:$line_no: label is required"
    return 1
  fi
  if [ "$description" = "" ]; then
    rig_print_error "$catalog_path:$line_no: description is required"
    return 1
  fi
  if [ "$command_text" = "" ]; then
    rig_print_error "$catalog_path:$line_no: command is required"
    return 1
  fi
  return 0
}

rig_validate_tools_catalog() {
  rig_validate_catalog "$1" "tools" \
    'category	id	label	kind	package	default	description	version_strategy	versions	notes' \
    10 2 rig_validate_tools_row
}

rig_validate_defaults_catalog() {
  rig_validate_catalog "$1" "macOS defaults" \
    'id	label	description	command	restart_hint' \
    5 1 rig_validate_defaults_row
}

rig_validate_catalogs() {
  rig_validate_tools_catalog "$(rig_tools_catalog_path)" || return 1
  rig_validate_defaults_catalog "$(rig_defaults_catalog_path)" || return 1
  return 0
}

rig_each_record() {
  local catalog_path line_no line
  catalog_path=$1
  line_no=0
  while IFS= read -r line || [ "$line" != "" ]; do
    line_no=$((line_no + 1))
    if [ "$line_no" -eq 1 ] || [ "$line" = "" ]; then
      continue
    fi
    rig_tsv_to_record "$line"
  done <"$catalog_path"
}

rig_each_tool() {
  rig_each_record "$(rig_tools_catalog_path)"
}

rig_each_default() {
  rig_each_record "$(rig_defaults_catalog_path)"
}

rig_lookup_record() {
  local producer wanted id_field record
  producer=$1
  wanted=$2
  id_field=$3
  while IFS= read -r record || [ "$record" != "" ]; do
    if [ "$record" = "" ]; then
      continue
    fi
    if [ "$(rig_record_field "$record" "$id_field")" = "$wanted" ]; then
      printf '%s\n' "$record"
      return 0
    fi
  done <<EOF
$("$producer")
EOF
  return 1
}

rig_lookup_tool() {
  rig_lookup_record rig_each_tool "$1" 2
}

rig_lookup_default() {
  rig_lookup_record rig_each_default "$1" 1
}

rig_default_exists() {
  rig_lookup_default "$1" >/dev/null 2>&1
}
