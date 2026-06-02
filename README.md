# rig

Set up a DevOps-ready Mac with the tools and versions your workflow depends on.

`rig` is a small, auditable macOS bootstrap tool for developers, DevOps
engineers, and platform engineers. The v1 design is captured in
[docs/rig-v1-spec.md](docs/rig-v1-spec.md).

## Status

This repository is in pre-release MVP development. The project spec is written,
and the first local `rig` command plus `install.sh` bootstrap foundation exist.
The MVP can validate the catalog, list tools, run diagnostics, and render dry-run
plans. It does **not** perform real workstation package installs yet.

Current MVP implementation:

- `install.sh --dry-run` renders the bootstrap plan without creating files, and
  `install.sh` can install or update the local `rig` command.
- `rig list`, `rig doctor`, `rig dry-run`, `rig install --dry-run`,
  `rig self-update`, and `rig version` are implemented.
- Dry-run output previews the selected Brewfile entries, external install plan,
  macOS defaults, and shell/profile edits without writing them.
- TSV catalog validation, multi-select flags, category/default filtering,
  macOS guards, bootstrap URL/branch checks, and command-path conflict checks are
  covered by local tests.

Remaining v1 work:

- real workstation package installation through Homebrew/Homebrew Bundle;
- interactive prompts with optional `gum` and a plain Bash fallback;
- writing and replaying `~/.config/rig/Brewfile`, external install-plan state,
  and `macos-defaults.sh`;
- a broader v1 catalog, supported version prompts, `rig update-tools`, and
  opt-in Homebrew auto-update setup.

The remote install one-liner reads `install.sh` from `main`. Review that exact
script before running it. Local dry-run testing from a clone is the safe path
while v1 is being built.

## Planned v1 Shape

`rig` will be a macOS-only bootstrap tool that:

- runs from the system `/bin/bash` on a clean Mac;
- uses Homebrew and Homebrew Bundle for Homebrew-native packages;
- supports interactive and non-interactive setup flows;
- includes a dry-run mode that makes no system or user changes;
- generates a committable `Brewfile`, external install plan, and macOS
  preferences script;
- uses a data-driven TSV catalog with descriptions for every selectable item;
- supports version-managed tools such as Node.js/npm, Bun, Terraform,
  OpenTofu, and Terragrunt;
- keeps tool self-updates separate from workstation package updates.

The planned bootstrap command is:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/vnedyalk0v/rig/main/install.sh)"
```

The planned dry-run bootstrap command is:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/vnedyalk0v/rig/main/install.sh)" -- --dry-run
```

Remote shell execution has real supply-chain risk. The installer should stay
small and readable, and users should review `install.sh` before running it.

## Available MVP Commands

```text
rig install --dry-run
rig dry-run
rig list
rig doctor
rig self-update
rig version
```

`rig install` without `--dry-run` intentionally exits with a deferred message in
this MVP.

## Planned v1 Commands

```text
rig install
rig install --dry-run
rig dry-run
rig list
rig doctor
rig self-update
rig update-tools
rig version
```

## Local Validation

```bash
for f in install.sh rig lib/rig/*.sh scripts/*.sh tests/*.sh; do
  bash -n "$f"
done
bash tests/run-tests.sh
./scripts/validate-catalog.sh
./rig dry-run --select vscode,chrome,node-npm --defaults finder-show-hidden-files
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
