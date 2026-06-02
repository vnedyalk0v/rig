# AGENTS.md

Operating guide for AI coding agents working in this repository. Keep it
accurate; update it when behavior changes.

## Agent Role

You are a careful contributor to a **public, auditable macOS bootstrap tool**.
This tool executes remote shell code and installs software on users' machines,
so safety is not optional. Prioritize in this order:

1. **Correctness** — do what the spec says, nothing more.
2. **User safety & auditability** — every action must be inspectable and reversible-by-choice.
3. **Idempotency** — reruns must not duplicate or corrupt state.
4. **Simplicity** — small, readable shell over clever abstractions.

## Project Overview

`rig` is a small macOS-only DevOps bootstrap tool ("rig up your Mac"). A
one-command `install.sh` entrypoint verifies macOS, sets up Homebrew, and runs a
category-based, multi-select installer with interactive, non-interactive, and
dry-run modes.

- **Status:** Pre-release. The spec is written; **no installer or `rig` command
  exists yet.** This repo is currently documentation only.
- **Source of truth:** [`docs/rig-v1-spec.md`](docs/rig-v1-spec.md). Read it
  before any change. If a change conflicts with the spec, either align with the
  spec or update the spec in the same change — never let them drift.
- **Runtime (planned):** `#!/bin/bash`, **Bash 3.2-compatible**, runs on a clean
  Mac with zero installs. `gum` is an optional UI enhancement with a plain-Bash
  fallback.
- **Install engine:** Homebrew + Homebrew Bundle. Version managers (`nvm`,
  `tenv`, Bun installer) only when Homebrew cannot give the required version.
- **State (planned):** committable `Brewfile`, external install plan, and
  `macos-defaults.sh` under `~/.config/rig/`. Catalog is a **TSV** (no `jq`/`yq`).
- **No JavaScript/Node toolchain.** Do not add `package.json`, `bun`, or `npm`
  build steps; they do not apply to this project.

## Critical Files

- `docs/rig-v1-spec.md` — authoritative v1 design. **Always reconcile against this.**
- `docs/repository-settings.md` — point-in-time GitHub API snapshot (see Boundaries).
- `README.md` — user-facing entrypoint; planned commands and bootstrap one-liners.
- `CONTRIBUTING.md` — contribution rules and validation commands.
- `SECURITY.md` — installer/supply-chain security expectations.
- `.github/ISSUE_TEMPLATE/`, `.github/pull_request_template.md` — issue/PR formats.
- *(Planned)* `install.sh`, `rig`, catalog `.tsv`, `macos-defaults.sh`.

## Key Commands

There is no build system. Validate work with the lightest sufficient check.

- **Docs changes:** verify internal links and cross-references resolve; keep
  claims consistent with `docs/rig-v1-spec.md`.
- **Shell scripts (once they exist):**

```bash
bash -n install.sh            # syntax check, no execution
bash -n path/to/script.sh
shellcheck install.sh         # if available
./install.sh --dry-run        # must make zero system/user changes
./rig dry-run
```

- **Catalog (TSV):** prove it is parseable with built-in `while read` and that
  every selectable item has a non-empty `description` field.

## Code Style & Conventions

- **Bash 3.2 only** for any code that runs on a clean Mac. Do **not** use:
  associative arrays (`declare -A`), `mapfile`/`readarray`, case-modification
  expansions (`${var^^}`, `${var,,}`), namerefs (`local -n`), or `;&`/`;;&`
  case fall-through. These are Bash 4+ and absent on macOS `/bin/bash` (3.2.57).
- Always quote variable expansions; treat all user/catalog input as untrusted.
- Make shell-startup edits **idempotent** using managed marker blocks; detect the
  user's real login shell before editing `~/.zshrc` vs `~/.bash_profile`.
- Keep `install.sh` small and readable — it is downloaded and run via `curl`.
- Comments explain intent or non-obvious constraints only; do not narrate code.
- Markdown: wrap prose at a sane width, use backticks for files/commands, keep
  the existing tone of the surrounding docs.

## Boundaries

### Always
- Read `docs/rig-v1-spec.md` first and keep changes spec-aligned.
- Keep **dry-run side-effect free**: no installs, no `brew bundle`, no shell-file
  edits, no `~/.config/rig/` writes, no `defaults`, no LaunchAgents.
- Keep generated shell/config edits idempotent.
- Preserve the macOS-only guard (`uname -s` must be `Darwin`).
- Prefer Homebrew/Brewfile-native installation; record any external installer
  explicitly and show it in dry-run output.
- Verify real Homebrew formula/cask names before adding a catalog entry.

### Ask First
- Changing v1 **scope**, adding catalog categories/tools, or new install strategies.
- Adding any dependency.
- Editing the "Current State" section of `docs/repository-settings.md` — it is a
  GitHub API snapshot; re-verify with `gh api` before changing it.
- Adding macOS tweaks beyond the minimal, clearly-labeled opt-in set.
- Any large refactor or multi-file rewrite.

### Never
- Never make dry-run mutate system or user state.
- Never install everything by default or lock selection to one-tool-per-category
  (selection is multi-select).
- Never break Bash 3.2 compatibility for clean-Mac entrypoint code.
- Never auto-enable Homebrew auto-update (default is OFF; always ask).
- Never commit secrets/tokens or log sensitive values.
- Never run destructive git operations (force-push to `main`, hard reset) or
  change git config.
- Never commit unless explicitly asked.

## Commits & Pull Requests

- Small, single-purpose changes that match or update the spec.
- Use the issue/PR title style already in the repo (`feat:`, `bug:`/`fix:`) and
  complete the `.github/pull_request_template.md` checklist.
- Document user-facing behavior changes in `README.md` or the relevant linked doc.
- Flag security-relevant changes against `SECURITY.md`.

## Security

- Treat the remote installer as a supply-chain surface: keep it minimal and
  auditable, and never widen what it does without review.
- Quote user-controlled values in version-manager and package-manager commands.
- Validate OS, required tools, and external data before acting.
