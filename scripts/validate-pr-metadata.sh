#!/bin/bash

set -u

base_ref=${BASE_REF:-}
head_ref=${HEAD_REF:-}
pr_title=${PR_TITLE:-}
head_repo=${HEAD_REPO:-}
base_repo=${BASE_REPO:-}
failures=0

error() {
  printf '::error::%s\n' "$*" >&2
  failures=$((failures + 1))
}

require_value() {
  name=$1
  value=$2
  if [ "$value" = "" ]; then
    error "$name is required"
  fi
}

require_value BASE_REF "$base_ref"
require_value HEAD_REF "$head_ref"
require_value PR_TITLE "$pr_title"

case "$base_ref" in
  dev)
    case "$head_ref" in
      feat/*|fix/*|bug/*|docs/*|chore/*|ci/*|refactor/*|main)
        ;;
      *)
        error "Pull requests into 'dev' must use a feature branch prefix: feat/, fix/, bug/, docs/, chore/, ci/, or refactor/. The only non-feature exception is main -> dev sync."
        ;;
    esac
    ;;
  main)
    if [ "$head_repo" != "" ] && [ "$base_repo" != "" ] && [ "$head_repo" != "$base_repo" ]; then
      error "Pull requests into 'main' must originate from this repository, not a fork."
    fi
    case "$head_ref" in
      dev|hotfix/*)
        ;;
      *)
        error "Pull requests into 'main' are only allowed from 'dev' or 'hotfix/*'. Open feature work against 'dev' instead."
        ;;
    esac
    ;;
esac

case "$pr_title" in
  feat:\ *|fix:\ *|bug:\ *|docs:\ *|chore:\ *|ci:\ *|refactor:\ *)
    ;;
  *)
    error "Pull request title must start with one of: feat:, fix:, bug:, docs:, chore:, ci:, or refactor:."
    ;;
esac

if [ "$failures" -eq 0 ]; then
  printf 'PR metadata policy passed\n'
  exit 0
fi

printf 'PR metadata policy failed with %s issue(s)\n' "$failures" >&2
exit 1
