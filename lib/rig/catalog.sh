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

rig_validate_tools_catalog() {
  catalog_path=$1
  expected_header='category	id	label	kind	package	default	description	version_strategy	versions	notes'

  if [ ! -f "$catalog_path" ]; then
    rig_print_error "tools catalog not found: $catalog_path"
    return 1
  fi

  line_no=0
  seen_ids='
'
  row_count=0

  while IFS= read -r line || [ "$line" != "" ]; do
    line_no=$((line_no + 1))
    if [ "$line_no" -eq 1 ]; then
      if [ "$line" != "$expected_header" ]; then
        rig_print_error "$catalog_path:1: invalid tools catalog header"
        return 1
      fi
      continue
    fi

    if [ "$line" = "" ]; then
      continue
    fi

    field_count=$(rig_field_count "$line")
    if [ "$field_count" != "10" ]; then
      rig_print_error "$catalog_path:$line_no: expected 10 tab-separated fields, got $field_count"
      return 1
    fi

    record=$(rig_tsv_to_record "$line")
    IFS="$RIG_TSV_DELIMITER" read -r category id label kind package default_flag description version_strategy _versions _notes <<EOF
$record
EOF

    if ! rig_validate_id "$category"; then
      rig_print_error "$catalog_path:$line_no: invalid category: $category"
      return 1
    fi
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
    row_count=$((row_count + 1))
  done <"$catalog_path"

  if [ "$row_count" -eq 0 ]; then
    rig_print_error "$catalog_path: catalog must contain at least one item"
    return 1
  fi

  return 0
}

rig_validate_defaults_catalog() {
  catalog_path=$1
  expected_header='id	label	description	command	restart_hint'

  if [ ! -f "$catalog_path" ]; then
    rig_print_error "macOS defaults catalog not found: $catalog_path"
    return 1
  fi

  line_no=0
  seen_ids='
'
  row_count=0

  while IFS= read -r line || [ "$line" != "" ]; do
    line_no=$((line_no + 1))
    if [ "$line_no" -eq 1 ]; then
      if [ "$line" != "$expected_header" ]; then
        rig_print_error "$catalog_path:1: invalid macOS defaults catalog header"
        return 1
      fi
      continue
    fi

    if [ "$line" = "" ]; then
      continue
    fi

    field_count=$(rig_field_count "$line")
    if [ "$field_count" != "5" ]; then
      rig_print_error "$catalog_path:$line_no: expected 5 tab-separated fields, got $field_count"
      return 1
    fi

    record=$(rig_tsv_to_record "$line")
    IFS="$RIG_TSV_DELIMITER" read -r id label description command_text _restart_hint <<EOF
$record
EOF

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
    row_count=$((row_count + 1))
  done <"$catalog_path"

  if [ "$row_count" -eq 0 ]; then
    rig_print_error "$catalog_path: catalog must contain at least one item"
    return 1
  fi

  return 0
}

rig_validate_catalogs() {
  rig_validate_tools_catalog "$(rig_tools_catalog_path)" || return 1
  rig_validate_defaults_catalog "$(rig_defaults_catalog_path)" || return 1
  return 0
}

rig_each_tool() {
  catalog_path=$(rig_tools_catalog_path)
  line_no=0
  while IFS= read -r line || [ "$line" != "" ]; do
    line_no=$((line_no + 1))
    if [ "$line_no" -eq 1 ] || [ "$line" = "" ]; then
      continue
    fi
    rig_tsv_to_record "$line"
  done <"$catalog_path"
}

rig_each_default() {
  catalog_path=$(rig_defaults_catalog_path)
  line_no=0
  while IFS= read -r line || [ "$line" != "" ]; do
    line_no=$((line_no + 1))
    if [ "$line_no" -eq 1 ] || [ "$line" = "" ]; then
      continue
    fi
    rig_tsv_to_record "$line"
  done <"$catalog_path"
}

rig_tool_exists() {
  wanted=$1
  while IFS="$RIG_TSV_DELIMITER" read -r _category id _label _kind _package _default_flag _description _version_strategy _versions _notes; do
    if [ "$id" = "$wanted" ]; then
      return 0
    fi
  done <<EOF
$(rig_each_tool)
EOF
  return 1
}

rig_default_exists() {
  wanted=$1
  while IFS="$RIG_TSV_DELIMITER" read -r id _label _description _command_text _restart_hint; do
    if [ "$id" = "$wanted" ]; then
      return 0
    fi
  done <<EOF
$(rig_each_default)
EOF
  return 1
}

rig_lookup_tool() {
  wanted=$1
  while IFS= read -r record || [ "$record" != "" ]; do
    IFS="$RIG_TSV_DELIMITER" read -r _category id _label _kind _package _default_flag _description _version_strategy _versions _notes <<EOF
$record
EOF
    if [ "$id" = "$wanted" ]; then
      printf '%s\n' "$record"
      return 0
    fi
  done <<EOF
$(rig_each_tool)
EOF
  return 1
}

rig_lookup_default() {
  wanted=$1
  while IFS= read -r record || [ "$record" != "" ]; do
    IFS="$RIG_TSV_DELIMITER" read -r id _label _description _command_text _restart_hint <<EOF
$record
EOF
    if [ "$id" = "$wanted" ]; then
      printf '%s\n' "$record"
      return 0
    fi
  done <<EOF
$(rig_each_default)
EOF
  return 1
}
