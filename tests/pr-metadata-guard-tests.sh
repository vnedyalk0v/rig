#!/bin/bash

set -u

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT=${TMPDIR:-/tmp}
TEST_TMP=$(mktemp -d "${TMP_ROOT%/}/rig-pr-guard-tests.XXXXXX")
failures=0

cleanup() {
  rm -rf "$TEST_TMP"
}

trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1"
  failures=$((failures + 1))
}

run_case() {
  name=$1
  expected_status=$2
  base_ref=$3
  head_ref=$4
  title=$5
  expected_text=$6
  output_file="$TEST_TMP/$name.out"

  BASE_REF=$base_ref \
    HEAD_REF=$head_ref \
    PR_TITLE=$title \
    HEAD_REPO=vnedyalk0v/rig \
    BASE_REPO=vnedyalk0v/rig \
    "$ROOT_DIR/scripts/validate-pr-metadata.sh" >"$output_file" 2>&1
  status=$?

  if [ "$expected_status" = "pass" ] && [ "$status" -eq 0 ]; then
    pass "$name status"
  elif [ "$expected_status" = "fail" ] && [ "$status" -ne 0 ]; then
    pass "$name status"
  else
    cat "$output_file"
    fail "$name status (exit $status)"
  fi

  if grep -F "$expected_text" "$output_file" >/dev/null 2>&1; then
    pass "$name message"
  else
    cat "$output_file"
    fail "$name message (missing: $expected_text)"
  fi
}

run_case \
  valid_feature_to_dev \
  pass \
  dev \
  feat/mvp-foundation \
  "feat: add rig MVP foundation" \
  "PR metadata policy passed"

run_case \
  invalid_codex_branch_to_dev \
  fail \
  dev \
  codex/mvp-foundation \
  "[codex] add rig MVP foundation" \
  "Pull requests into 'dev' must use a feature branch prefix"

run_case \
  invalid_codex_title_to_dev \
  fail \
  dev \
  feat/mvp-foundation \
  "[codex] add rig MVP foundation" \
  "Pull request title must start with one of"

run_case \
  valid_main_to_dev_sync \
  pass \
  dev \
  main \
  "chore: sync main into dev" \
  "PR metadata policy passed"

run_case \
  valid_dev_to_main_promotion \
  pass \
  main \
  dev \
  "chore: promote dev to main" \
  "PR metadata policy passed"

run_case \
  invalid_feature_to_main \
  fail \
  main \
  feat/mvp-foundation \
  "feat: add rig MVP foundation" \
  "Pull requests into 'main' are only allowed from 'dev' or 'hotfix/*'"

if [ "$failures" -eq 0 ]; then
  printf 'All PR metadata guard tests passed\n'
  exit 0
fi

printf '%s PR metadata guard test(s) failed\n' "$failures"
exit 1
