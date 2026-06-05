# Security Policy

`rig` is a macOS bootstrap tool that installs developer tools, edits managed
shell startup blocks, generates local configuration, and optionally applies
macOS defaults. Security reports for this project should treat installer
behavior and supply-chain behavior as sensitive.

## Supported Versions

The project is pre-release. Until tagged releases exist, only the current
`main` branch is in scope for security fixes.

## Current MVP Security Posture

The implemented security-sensitive surfaces are the remote bootstrap script,
local tool bootstrap/update, CLI argument parsing, catalog parsing, dry-run
rendering, generated config writes under the rig config directory, Homebrew
Bundle apply, external install-plan replay, managed shell startup blocks,
opt-in macOS defaults scripts, optional Homebrew auto-update setup, and
`rig self-update`.

Keep the current protections covered: non-macOS commands fail before rendering
plans or invoking update work, dry-run paths create no user or system state,
Homebrew installation requires interactive approval or explicit `--yes`,
generated shell edits stay idempotent, install-plan replay validates catalog
identity and strategy before invoking external installers, unsafe bootstrap
repository URLs and option-like branch names are rejected, and command-path
conflicts fail before clone/update work.

## Reporting a Vulnerability

Use GitHub private vulnerability reporting for this repository if it is
available:

<https://github.com/vnedyalk0v/rig/security/advisories/new>

If private reporting is not available, open a public issue with only a short
non-sensitive summary and ask for a private reporting channel. Do not include
exploit steps, payloads, secret material, or instructions that would put users
at immediate risk.

Please include:

- the affected command, script, or document;
- the macOS version and shell if relevant;
- whether the issue affects dry-run, install, self-update, generated shell
  configuration, or external installer handling;
- a minimal proof of impact without real secrets.

## In Scope

- Remote bootstrap and installer behavior.
- Command injection, quoting, PATH, and shell startup file issues.
- Dry-run paths that accidentally mutate the system or user configuration.
- Unsafe external installer invocation.
- Brewfile, catalog, and generated install-plan handling.
- Self-update behavior.
- Secret exposure in logs, generated files, or diagnostics.

## Out of Scope

- Bugs in third-party tools installed by Homebrew or vendor installers.
- Social engineering reports without a technical vulnerability in this repo.
- Denial-of-service issues that only affect the reporter's local machine.
- Company fleet provisioning gaps; MDM and enterprise management are outside
  the v1 scope.

## Security Expectations For Changes

Contributions should preserve these rules:

- `--dry-run` must not install packages, write generated state, edit shell
  files, apply `defaults`, or create LaunchAgents.
- Missing Homebrew must not be installed silently; require an interactive
  approval prompt or explicit `--yes`.
- Shell edits must be idempotent and use managed markers.
- External installers must be explicit, documented, and shown in dry-run output.
- Version-manager and package-manager commands must quote user-controlled
  values safely.
- The installer must fail clearly on non-macOS systems.
