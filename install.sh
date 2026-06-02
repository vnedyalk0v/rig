#!/bin/bash

set -u

repo_url=https://github.com/vnedyalk0v/rig.git
branch=main
dry_run=no

usage() {
  cat <<'EOF'
Usage:
  install.sh [--dry-run] [--repo-url <url>] [--branch <name>]

Installs or updates the local rig command under:
  ~/.local/share/rig
  ~/.local/bin/rig

In this MVP, workstation package installs are deferred. Use --dry-run to inspect
the bootstrap steps without creating or changing files.
EOF
}

error() {
  printf 'install.sh: %s\n' "$*" >&2
}

validate_branch_name() {
  case "$1" in
    ""|-*|/*|*/|*..*|*[!A-Za-z0-9._/-]*)
      return 1
      ;;
  esac
  return 0
}

validate_repo_url() {
  case "$1" in
    https://*|git@github.com:*)
      return 0
      ;;
  esac
  return 1
}

require_macos() {
  if [ "$(uname -s 2>/dev/null)" != "Darwin" ]; then
    error "rig supports macOS only; detected $(uname -s 2>/dev/null)"
    exit 1
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      dry_run=yes
      shift
      ;;
    --repo-url)
      if [ "$#" -lt 2 ]; then
        error "--repo-url requires a value"
        exit 1
      fi
      repo_url=$2
      shift 2
      ;;
    --branch)
      if [ "$#" -lt 2 ]; then
        error "--branch requires a value"
        exit 1
      fi
      branch=$2
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      error "unknown argument: $1"
      usage >&2
      exit 1
      ;;
  esac
done

if ! validate_branch_name "$branch"; then
  error "invalid branch name: $branch"
  exit 1
fi

if ! validate_repo_url "$repo_url"; then
  error "invalid repo URL: $repo_url"
  exit 1
fi

if [ "${HOME:-}" = "" ]; then
  error "HOME is required"
  exit 1
fi

install_root=${HOME}/.local/share/rig
bin_dir=${HOME}/.local/bin
rig_link=${bin_dir}/rig
rig_target=${install_root}/rig

if [ "$dry_run" = "yes" ]; then
  printf 'rig bootstrap dry-run\n'
  printf 'Dry run: no files will be created or changed\n'
  printf '[plan] verify macOS with uname -s\n'
  printf '[plan] require git for non-dry bootstrap\n'
  printf '[plan] clone or update %s branch %s into %s\n' "$repo_url" "$branch" "$install_root"
  printf '[plan] create symlink %s -> %s\n' "$rig_link" "$rig_target"
  printf '[plan] run %s dry-run for workstation install previews\n' "$rig_link"
  exit 0
fi

require_macos

if ! command -v git >/dev/null 2>&1; then
  error "git is required to clone or update rig"
  exit 1
fi

mkdir -p "$install_root" "$bin_dir" || exit 1

if [ -d "$install_root/.git" ]; then
  (
    cd "$install_root" || exit 1
    git fetch origin "$branch" || exit 1
    git checkout "$branch" || exit 1
    git pull --ff-only origin "$branch" || exit 1
  ) || exit 1
elif [ -e "$install_root" ] && [ "$(find "$install_root" -mindepth 1 -maxdepth 1 2>/dev/null)" != "" ]; then
  error "$install_root exists but is not a rig git clone; refusing to overwrite it"
  exit 1
else
  rmdir "$install_root" 2>/dev/null || true
  git clone --branch "$branch" -- "$repo_url" "$install_root" || exit 1
fi

if [ -L "$rig_link" ]; then
  existing_target=$(readlink "$rig_link")
  if [ "$existing_target" != "$rig_target" ]; then
    error "$rig_link already points to $existing_target; refusing to overwrite it"
    exit 1
  fi
elif [ -e "$rig_link" ]; then
  error "$rig_link already exists and is not a symlink; refusing to overwrite it"
  exit 1
else
  ln -s "$rig_target" "$rig_link" || exit 1
fi

printf 'rig command installed at %s\n' "$rig_link"
printf 'Real workstation installs are deferred in this MVP. Run: %s dry-run\n' "$rig_link"
