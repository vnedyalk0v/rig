# rig

Set up a DevOps-ready Mac with the tools and versions your workflow depends on.

`rig` is a small, auditable macOS bootstrap tool for developers, DevOps
engineers, and platform engineers. The v1 design is captured in
[docs/rig-v1-spec.md](docs/rig-v1-spec.md).

## Status

This repository is in pre-release v1 development. The bootstrap installer,
local `rig` command, catalog, dry-run planning, config generation, and real
install paths are implemented.

Current implementation:

- `install.sh --dry-run` renders the bootstrap plan without creating files, and
  `install.sh` installs or updates the local `rig` command before starting
  `rig install`.
- `rig install` writes committable state under `~/.config/rig/` (Brewfile,
  install-plan.tsv, macos-defaults.sh) and applies it via Homebrew Bundle,
  version managers, and defaults scripts.
- `rig install` checks Homebrew before tool selection. If Homebrew is missing,
  interactive install asks before installing it; non-interactive install
  requires `--yes`.
- `rig install --dry-run`, `rig install --write-config-only`, and
  `rig install --from-config` support preview, config-only, and replay flows.
- `rig list`, `rig doctor`, `rig dry-run`, `rig self-update`, `rig update-tools`,
  and `rig version` are implemented.
- Interactive install (no flags) uses optional `gum` with a plain Bash keyboard
  checklist fallback and a final review screen.
- Non-interactive selection uses `--select`, `--defaults`, `--category`, and
  `--version` flags.
- TSV catalog validation, multi-select flags, macOS guards, and bootstrap checks
  are covered by local tests.

Remaining polish:

- expand catalog coverage toward the full v1 breadth (incremental, verify-first);
- additional macOS defaults and category entries from the spec as they are verified.

The remote install one-liner reads `install.sh` from `main`. Review that exact
script before running it. Use `rig install --dry-run` to preview workstation
changes before applying them.

## v1 Shape

`rig` is a macOS-only bootstrap tool that:

- runs from the system `/bin/bash` on a clean Mac;
- uses Homebrew and Homebrew Bundle for Homebrew-native packages;
- supports interactive and non-interactive setup flows;
- includes a dry-run mode that makes no system or user changes;
- generates a committable `Brewfile`, external install plan, and macOS
  preferences script under `~/.config/rig/`;
- uses a data-driven TSV catalog with descriptions for every selectable item;
- supports version-managed tools such as Node.js/npm, Bun, Terraform,
  OpenTofu, and Terragrunt;
- keeps tool self-updates separate from workstation package updates.

The bootstrap command is:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/vnedyalk0v/rig/main/install.sh)"
```

That command installs or updates the local `rig` command and then starts the
interactive setup flow. The flow checks for Homebrew first. If `brew` is
missing, `rig` explains that Homebrew is required and waits for approval before
running the official Homebrew installer. After Homebrew is available, `rig`
shows the selectable tool/software catalog.

The dry-run bootstrap command is:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/vnedyalk0v/rig/main/install.sh)" -- --dry-run
```

Remote shell execution has real supply-chain risk. The installer should stay
small and readable, and users should review `install.sh` before running it.
After bootstrap, use `rig install --dry-run` to exercise the same Homebrew
prerequisite and selection flow without installing packages or writing config.

## Commands

```text
rig install
rig install --dry-run
rig install --yes --select gh
rig install --write-config-only
rig install --from-config
rig dry-run
rig list
rig doctor
rig self-update
rig update-tools
rig version
```

Run `rig install` with no flags for an interactive setup. Use
`rig install --dry-run` or `rig dry-run` to preview without changes. Use
`--yes` only when a non-interactive install is allowed to install Homebrew if it
is missing.

Interactive selection requires a real terminal. The plain Bash fallback renders
checkbox-style multi-select lists by category: use Up/Down to move, Space to
select or deselect, and Enter to continue. Rows show the tool name, catalog id,
and description without requiring numeric input. Before applying an interactive
install, `rig` shows a final review grouped by category and asks for approval.
If `gum` is installed, `rig` uses its multi-select UI. In scripts, CI, or
captured shells, pass explicit `--select` and `--defaults` flags instead of
relying on prompts.

Dry-run output starts with a short summary of package counts before printing the
raw Brewfile, external install plan, macOS defaults, and shell-edit preview.

## Local Validation

```bash
for f in install.sh rig lib/rig/*.sh scripts/*.sh tests/*.sh; do
  bash -n "$f"
done
bash tests/run-tests.sh
./scripts/validate-catalog.sh
./rig install --dry-run --select vscode,chrome,node-npm --defaults finder-show-hidden-files
./install.sh --dry-run
shellcheck install.sh rig lib/rig/*.sh scripts/*.sh tests/*.sh
actionlint .github/workflows/*.yml
git diff --check
```

## Design Principles

- **Auditable:** keep bootstrap code and generated state easy to inspect.
- **Dry-run first:** every install path should be explainable before it runs.
- **Idempotent:** reruns should not duplicate shell config or generated files.
- **Portable on macOS:** use Bash 3.2-compatible shell code for the entrypoint.
- **Explicit:** do not install everything by default; make users choose.

## Documentation

- [v1 specification](docs/rig-v1-spec.md)
- [Repository settings record](docs/repository-settings.md)
- [Contributing guide](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Support guide](SUPPORT.md)
- [Code of conduct](CODE_OF_CONDUCT.md)
- [Agent instructions](AGENTS.md) — guidance for AI coding agents

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). While v1 is being built, small,
spec-aligned pull requests are preferred. Branch off `dev` and open pull
requests against `dev` (the default branch); `main` is the stable release
branch. [CodeRabbit](https://coderabbit.ai) automatically reviews every pull
request.

## Security

See [SECURITY.md](SECURITY.md). Please do not report exploitable security
issues in public GitHub issues.

## Support

See [SUPPORT.md](SUPPORT.md) for where to ask questions or report non-sensitive
problems.

## License

MIT. See [LICENSE](LICENSE).
