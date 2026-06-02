#!/bin/bash

set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
RIG_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)

. "$RIG_ROOT/lib/rig/common.sh"
. "$RIG_ROOT/lib/rig/catalog.sh"

tools_catalog=$(rig_tools_catalog_path)
defaults_catalog=$(rig_defaults_catalog_path)

while [ "$#" -gt 0 ]; do
  case "$1" in
    --tools)
      if [ "$#" -lt 2 ]; then
        rig_print_error "--tools requires a path"
        exit 1
      fi
      tools_catalog=$2
      shift 2
      ;;
    --defaults)
      if [ "$#" -lt 2 ]; then
        rig_print_error "--defaults requires a path"
        exit 1
      fi
      defaults_catalog=$2
      shift 2
      ;;
    --help|-h)
      printf 'Usage: validate-catalog.sh [--tools <path>] [--defaults <path>]\n'
      exit 0
      ;;
    *)
      rig_print_error "unknown argument: $1"
      exit 1
      ;;
  esac
done

rig_validate_tools_catalog "$tools_catalog" || exit 1
rig_validate_defaults_catalog "$defaults_catalog" || exit 1

printf 'Catalog validation passed\n'
