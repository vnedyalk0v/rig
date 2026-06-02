# rig

Set up a DevOps-ready Mac with the tools and versions your workflow depends on.

`rig` is a small, auditable macOS bootstrap tool for developers, DevOps
engineers, and platform engineers. The v1 design is captured in
[docs/rig-v1-spec.md](docs/rig-v1-spec.md).

## Status

This repository is in the v1 planning stage. The project spec is written, but
the installer and `rig` command are not implemented yet.

Do not run a remote installer for this repository until `install.sh` exists in
`main` and you have reviewed it.

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

## Planned Commands

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

## Design Principles

- **Auditable:** keep bootstrap code and generated state easy to inspect.
- **Dry-run first:** every install path should be explainable before it runs.
- **Idempotent:** reruns should not duplicate shell config or generated files.
- **Portable on macOS:** use Bash 3.2-compatible shell code for the entrypoint.
- **Explicit:** do not install everything by default; make users choose.

## Documentation

- [v1 specification](docs/rig-v1-spec.md)
- [Repository settings recommendations](docs/repository-settings.md)
- [Contributing guide](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Support guide](SUPPORT.md)
- [Code of conduct](CODE_OF_CONDUCT.md)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). While v1 is being built, small,
spec-aligned pull requests are preferred.

## Security

See [SECURITY.md](SECURITY.md). Please do not report exploitable security
issues in public GitHub issues.

## Support

See [SUPPORT.md](SUPPORT.md) for where to ask questions or report non-sensitive
problems.

## License

MIT. See [LICENSE](LICENSE).
