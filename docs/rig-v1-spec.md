# rig — macOS DevOps Bootstrap Tool

Date: 2026-06-02

## Summary

`rig` is a small, auditable macOS bootstrap tool. A one-command entrypoint downloads a repo-managed installer, verifies it is running on macOS, then starts a setup flow — interactive by default, with a non-interactive mode for automation — where the user chooses what to install by category. It also has a dry-run mode that simulates the selected install plan without changing the operating system. The name comes from "rig up your Mac."

The tool does not install everything by default. It presents categories such as shells and terminals, IDEs, AI tools, browsers, communication apps, JavaScript runtimes/package managers, DevOps and infrastructure CLIs, Kubernetes tools, containers, productivity/security apps, fonts, and a small set of opt-in macOS preferences. Selected items are installed through Homebrew and Homebrew Bundle where possible, and through explicit version managers or vendor installers when Homebrew cannot provide the requested version behavior. Every selectable tool or app includes a brief description.

This is built as a **polished public / open-source tool**, not an enterprise provisioning system.

Recommended v1 shape:

- A public GitHub repo with a small `install.sh` entrypoint.
- A one-command install documented in the README.
- A local clone under the user home directory for repeat runs and self-update.
- A category-based catalog of installable tools.
- An interactive prompt layer with a nice UI when possible and a plain shell fallback.
- A non-interactive mode for automation and reproducible re-runs.
- A dry-run command/flag that prints the planned actions without installing packages or writing system/user configuration.
- Homebrew Bundle as the install engine for formulae, casks, VS Code extensions, Mac App Store apps, and services.
- A committable package/config state: `Brewfile`, external install plan, version-manager selections, and a separate macOS preferences script.
- A `rig self-update` command that updates the local tool clone.

## Current Implementation Status

As of 2026-06-02, v1 core install functionality is implemented:

Implemented:

- `install.sh --dry-run` and bootstrap clone/symlink for the local `rig` command,
  followed by the `rig install` setup flow in normal bootstrap mode.
- `rig install` (interactive and flag-driven), config writes under
  `~/.config/rig/`, Homebrew Bundle apply, external install-plan replay
  (nvm, tenv, bun), macOS defaults script generation/apply, and idempotent shell
  profile managed blocks.
- Homebrew prerequisite preflight before interactive selection, with explicit
  approval in interactive mode and `--yes` for non-interactive installation.
- `rig list`, `rig doctor`, `rig dry-run`, `rig install --dry-run`,
  `rig install --write-config-only`, `rig install --from-config`,
  `rig self-update`, `rig update-tools`, and `rig version`.
- Interactive prompts with optional `gum` and plain Bash fallback; non-interactive
  `--select`, `--defaults`, `--category`, and `--version` flags.
- Opt-in Homebrew auto-update via `--auto-update` (default OFF).
- TSV catalog validation, dry-run previews, macOS guards, and regression tests.

Remaining incremental work:

- expand catalog toward full v1 category breadth (verify each formula/cask first);
- additional AI/vendor external installers deferred until a single tested pattern exists.

## Finalized Decisions (v1)

These were settled during brainstorming and drive the implementation:

- **Audience:** Polished public / open-source tool that anyone can use.
- **Name / command:** `rig`.
- **Runtime:** Written as a `#!/bin/bash`, Bash 3.2-compatible script so it runs on a clean Mac with zero installs. `gum` is an optional UI enhancement with a plain-Bash fallback. The tool detects the user's real login shell (usually Zsh on modern macOS) to know which startup file to edit.
- **Catalog format:** TSV (no `jq`/`yq` dependency on a fresh Mac).
- **Reproducibility:** A committable `Brewfile` is the source of truth for selected Homebrew-native packages (restored with `brew bundle`); a separate install-plan file records version-managed and external tools; a re-runnable `macos-defaults.sh` records opt-in macOS tweaks, since a `Brewfile` cannot express those. `rig` orchestrates all of them. v1 manages a single configuration per machine, not multiple named profiles.
- **Modes:** Interactive prompts plus a non-interactive mode (flags, an existing rig config, a bring-your-own Brewfile, or a bring-your-own install plan).
- **Dry-run:** `rig dry-run` and `rig install --dry-run` simulate the selected setup without installing packages, running `brew bundle`, editing shell startup files, writing `~/.config/rig/`, applying macOS defaults, creating LaunchAgents, or otherwise changing the operating system. The output shows what would happen, including the Homebrew prerequisite step, selected packages, generated Brewfile content, shell/profile edits, macOS preference changes, and update-automation changes.
- **Selection:** Multi-select within each category — the user can choose one, several, or all tools per category (e.g. multiple IDEs or multiple browsers), never one-per-category.
- **Descriptions:** Every catalog item has a short description shown in prompts, lists, and dry-run output so users understand what they are selecting.
- **Versioned developer tools:** Node.js/npm, Bun, Terraform, OpenTofu, Terragrunt, and Terraspace are selectable catalog items. `rig` asks for "latest" or a specific version where the chosen install strategy supports it. Use `nvm` for Node.js/npm. Use `tenv` for Terraform, OpenTofu, and Terragrunt version management; `tenv` also supports Atmos if that tool is added later. Use Bun's official installer for specific Bun versions and Homebrew only when the user wants the latest Homebrew-managed Bun. Terraspace is latest-only in v1 through its Homebrew tap unless a safe, maintainable version-pinning path is explicitly added.
- **macOS preferences:** Included in v1 but minimal — a few safe, popular, clearly-labeled opt-in tweaks only.
- **Auto-update:** The tool asks before enabling any automatic Homebrew updates; default is OFF.

## One-Command Bootstrap Model

The public entrypoint can be a command like:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/vnedyalk0v/rig/main/install.sh)"
```

The same entrypoint should support a dry-run argument for safe testing:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/vnedyalk0v/rig/main/install.sh)" -- --dry-run
```

This is common in the macOS/Homebrew ecosystem, but it has a security tradeoff: the user is executing remote shell code. The README should clearly link to the script source and explain what it does. For a public tool, the downloaded `install.sh` should stay small and readable.

The remote bootstrap script should only do the minimum:

- Verify the OS is macOS.
- Verify required system tools exist or provide a clear error.
- Parse bootstrap arguments such as `--dry-run` before doing any install or clone step.
- Check Homebrew before tool selection. If Homebrew is missing, ask the user
  before installing it; non-interactive installs require explicit `--yes`.
  Dry-run mode prints the same prerequisite decision path without installing
  Homebrew.
- Clone or update the bootstrap repo under the user's home directory, except
  in dry-run mode. Existing clones must have an `origin` that canonically
  matches the requested or default GitHub repository before any fetch, pull, or
  local `rig` execution. The trusted origin is recorded in the local clone for
  later self-update validation.
- Add or suggest a command path such as `~/.local/bin/rig`, except in dry-run mode.
- Start the interactive installer, or print the equivalent planned steps in dry-run mode.

## Runtime and Shell Detection

The tool supports macOS only. It checks `uname -s` and exits early unless the value is `Darwin`.

**Important shell facts (verified):**

- Since macOS Catalina (10.15, 2019), the **default interactive/login shell is Zsh**, not Bash. New user accounts get Zsh.
- However, the **`/bin/bash` binary (version 3.2.57, 2007) is still bundled** with every macOS for backward compatibility. A `#!/bin/bash` script still runs on a clean Mac with nothing installed. `/bin/sh`, `/bin/dash`, and `/bin/zsh` are also always present.

This produces a clean separation:

- **Script runtime:** the `/bin/bash` 3.2 binary that always ships. The tool is written to be Bash 3.2-compatible so it needs zero installs to start. This matches Homebrew's own official installer, which is also a `/bin/bash` script.
- **User's shell:** usually Zsh. The tool detects the login shell from `$SHELL` (and the running process where practical) to decide which startup file to edit, e.g. `~/.zshrc` vs `~/.bash_profile`.

The main supported login shells are Zsh and Bash. Fish, Nushell, or other shells should receive a clear warning rather than silently editing the wrong startup files.

Shell configuration must be idempotent. Any PATH block or autocomplete setup uses managed markers so rerunning the installer does not duplicate lines.

## Homebrew as the Install Foundation

Homebrew remains the right foundation for this type of DevOps workstation automation on macOS.

Current Homebrew documentation shows the official install command:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

The official installation docs also note the default supported prefixes:

- Apple Silicon: `/opt/homebrew`
- Intel macOS: `/usr/local`

`rig` should handle both paths and run the equivalent of `brew shellenv` after installation so the current session can use `brew` immediately.

Homebrew installation is a prerequisite step, not an implicit side effect of
package apply. If `brew` is already available, `rig` reports the detected path
and continues. If `brew` is missing during an interactive install, `rig` explains
that Homebrew is required and asks before invoking the official installer. In
non-interactive install mode, `rig` must not prompt or silently install
Homebrew; it fails unless the user provided `--yes`. Dry-run mode prints the
same prerequisite step and never invokes the Homebrew installer.

## Homebrew Bundle and Brewfile Strategy

Homebrew Bundle is the strongest install engine for the Homebrew-native part of this project because it gives a declarative install format while still supporting many package types.

Current Homebrew Bundle documentation says Brewfiles can include:

- Formulae with `brew`
- GUI apps with `cask`
- Taps
- Mac App Store apps with `mas`
- VS Code extensions with `vscode`
- Go packages
- Cargo packages
- uv tools
- krew kubectl plugins
- Background services through `brew services`

The interactive tool collects the user's choices and generates the canonical `Brewfile` (see Reproducibility) for the selected items that Homebrew Bundle can express. This keeps the installer flexible while still relying on Homebrew's proven install behavior.

Some requested developer and AI tools may need a versioned installer, an npm/Bun-based installer, or a vendor-specific installer instead of a plain Brewfile entry. Those items still live in the same catalog, but their install strategy must be explicit and auditable. v1 should prefer Homebrew/Brewfile-native installation when available; if a tool cannot be installed that way, `rig` records and displays the separate install step and includes it in dry-run output.

Generated Brewfile entries use non-interpolating Ruby string forms and strict
catalog validation for Brewfile-native package names and labels. Catalog data
must not be able to introduce Ruby interpolation or other executable Brewfile
DSL content.

## Version Manager Strategy

Homebrew Bundle is not a version lockfile. It can install current formulae/casks and avoid upgrades with `--no-upgrade`, but it does not provide arbitrary package-version selection. Tools where the user naturally expects "latest or a specific version" need dedicated version-management behavior:

- **Node.js/npm:** Install and manage through `nvm`. The user chooses latest/LTS or a specific Node.js version; npm comes with the selected Node.js version, and `rig` may optionally update npm within that Node installation if the user requests a specific npm version.
- **Terraform, OpenTofu, Terragrunt:** Install `tenv` and use it to install/switch versions. This is preferred over plain `brew install terraform`, because Homebrew core's Terraform formula is disabled/stuck on the last MPL-licensed release. `tenv` is also the better successor-style choice over separate `tfenv`/`tofuenv` for a public tool because it manages Terraform, OpenTofu, Terragrunt, Terramate, and Atmos with one binary.
- **Bun:** Use Bun's official installer when a specific Bun version is requested. Use Homebrew only for the "latest Homebrew-managed Bun" path.
- **Terraspace:** Install latest through the official Terraspace Homebrew tap in v1. Specific Terraspace version management is deferred unless the implementation adds a RubyGems/Bundler-based path with clear tradeoffs.

The external install plan records the chosen version manager, selected tool, selected version/channel, and any shell initialization changes needed to make the selected version available.

## Reproducibility: Committable Brewfile + macOS Preferences Script

Reproducibility is the core value of a bootstrap tool. A `Brewfile` is the de-facto standard for declaring Homebrew packages, but it cannot express macOS system settings or external version-manager choices, so `rig` keeps state in committable files under `~/.config/rig/`:

- **Brewfile (canonical for packages):** Selected formulae, casks, Mac App Store apps, and VS Code extensions are written to a `Brewfile`. This is the source of truth for packages, restored on any machine with `brew bundle --file=~/.config/rig/Brewfile`.
- **External install plan:** Selected tools that cannot be represented in a Brewfile are written to a separate, auditable install-plan file with the chosen install strategy and version. `rig` replays that file after the Brewfile step and includes it in dry-run output.
- **macOS preferences script:** The chosen opt-in tweaks are written to a
  re-runnable, idempotent `macos-defaults.sh` (a `Brewfile` cannot represent
  `defaults write` settings). The script is generated from structured catalog
  fields, not raw shell command text, and replay rejects non-generated command
  shapes before executing the script.

`rig` orchestrates these files during install. The user can commit them to their own dotfiles repo and replay them on a brand-new machine. v1 manages a single configuration per machine; multiple named profiles are out of scope.

## Interactive and Non-Interactive Modes

**Interactive (default):** The installer asks questions by category instead of presenting one huge list. Within each category the user can select **one, several, or all** items — selection is multi-select, never locked to a single tool per category. For example, under IDEs a user can pick both Visual Studio Code and Cursor; under browsers they can pick Chrome, Firefox, and Brave together. Versioned tools such as Node.js/npm, Bun, Terraform, OpenTofu, and Terragrunt ask a follow-up version question when the selected install strategy supports it. With `gum`, this maps to a multi-select (`gum choose --no-limit`) checklist; the plain-Bash fallback renders a keyboard checklist where Up/Down moves, Space toggles selection, and Enter continues. The fallback rows show the tool label, catalog id, and description without requiring numeric input.

Example categories:

- Shell and terminal: iTerm2, Ghostty, WezTerm, Warp, Starship, Oh My Zsh, completion helpers.
- IDEs/editors: Visual Studio Code, Cursor, Kiro, JetBrains Toolbox, Zed.
- AI tools: Codex CLI, Codex Desktop, Claude Code CLI, Claude Desktop / Claude Code desktop workflow, Pi Coding Agent, OpenCode.
- Browsers: Google Chrome, Firefox, Brave, Zen.
- Communication: Slack, Microsoft Teams, Discord, Zoom.
- JavaScript runtimes/package managers: Node.js/npm, Bun.
- DevOps CLI: GitHub CLI, AWS CLI, Azure CLI, Google Cloud SDK, Packer.
- Infrastructure as code: Terraform, OpenTofu, Terraspace, Terragrunt.
- Kubernetes: kubectl, Helm, k9s, kubectx, kubens, kind, minikube.
- Containers: Docker Desktop, Colima, Lima, Podman Desktop.
- Productivity/security: 1Password, Bitwarden, Rectangle, Raycast.
- Fonts: JetBrains Mono, Fira Code, Hack Nerd Font.
- macOS preferences: a few minimal, opt-in tweaks (see below).

For prompt UI, `gum` is an optional dependency. Its project provides ready-to-use shell utilities for choices, confirmations, and input prompts. `rig` uses `gum` when available in a real terminal, and provides a plain Bash fallback so the installer still works on a clean Mac before anything is installed. The plain Bash fallback renders checkbox-style multi-select lists with keyboard navigation and does not require typing package numbers. Interactive installs show a final review grouped by category before writing config or applying packages; actual installs require approval at that review step.

Interactive selection requires a real terminal. If `rig install` or
`rig install --dry-run` would need prompts but stdin is not a terminal, `rig`
exits with a clear error instead of dumping every category. Automation should
use explicit `--select`, `--defaults`, `--category`, and `--version` flags or
`--from-config`.

**Non-interactive:** For automation and reproducible re-runs, `rig` also supports a non-interactive mode driven by any of:

- Command-line flags.
- An existing rig configuration (the `Brewfile`, external install plan, and `macos-defaults.sh` under `~/.config/rig/`).
- A user-supplied `Brewfile` and/or install plan (bring-your-own).

In non-interactive mode there are no prompts; selections come from the chosen
source. If Homebrew is missing and the command will actually install packages,
the user must pass `--yes` to approve installing Homebrew.

**Dry-run:** Dry-run is available for both interactive and non-interactive flows. It validates the requested selections, resolves package/install strategies, and prints the exact install plan, but it must not run installers or write generated state. Dry-run output starts with a short summary of counts, then prints the raw Brewfile, external install plan, macOS defaults, and shell/profile edit preview for auditability. This is the safe test path for demos, CI smoke checks, and verifying that the catalog and prompt logic work without changing the user's Mac.

## Catalog Design

The install catalog is data-driven, not hardcoded into the prompt flow.

For v1, a **TSV file** is the right choice because a fresh Mac has the tools to parse it (built-in `while read`) before any extra dependencies are installed. YAML would need `yq` and JSON would need `jq`, neither of which exists on a clean install — a chicken-and-egg problem.

Recommended catalog fields:

```text
category	id	label	kind	package	default	description	version_strategy	versions	min_macos	arch	notes
```

The `description` field is required and should be short enough to show inside
prompts, `rig list`, and dry-run output. `version_strategy` explains whether
the tool is installed as the current Homebrew/package-manager version or whether
the user can choose from supported versions. `versions` is empty for unversioned
items and a catalog-maintained list for tools where version selection is
supported. `min_macos` is empty for normal entries and set to the minimum
supported macOS major version when Homebrew or the vendor requires one. `arch`
is empty for normal entries and set to a required machine architecture such as
`arm64` when Homebrew or the vendor requires one. Selected entries with unmet
`min_macos` or `arch` fail before writing config or rendering an install plan.

Example rows:

```text
ide	vscode	Visual Studio Code	cask	visual-studio-code	yes	General-purpose code editor	homebrew-latest				Verify cask name
ide	cursor	Cursor	cask	cursor	no	AI-assisted code editor	homebrew-latest				Verify cask name
ide	antigravity-ide	Antigravity	cask	antigravity-ide	no	Google AI coding agent IDE	homebrew-latest				Verify cask name
ide	kiro	Kiro	cask	kiro	no	Agentic IDE	homebrew-latest				Verify cask name
ide	sublime-text	Sublime Text	cask	sublime-text	no	Text editor for code, markup, and prose	homebrew-latest				Verify cask name
terminal	ghostty	Ghostty	cask	ghostty	no	GPU-accelerated terminal emulator	homebrew-latest				Verify cask name
terminal	warp	Warp	cask	warp	no	Rust-based terminal	homebrew-latest				Verify cask name
ai	codex-cli	Codex CLI	cask	codex	no	OpenAI command-line coding agent	homebrew-latest				Verify current cask/formula choice
ai	codex-desktop	Codex Desktop	cask	codex-app	no	Desktop app for managing Codex coding agents	homebrew-latest				Verify current cask name
ai	chatgpt-desktop	ChatGPT Desktop	cask	chatgpt	no	OpenAI ChatGPT desktop app, separate from Codex; requires macOS 14+ and Apple Silicon	homebrew-latest		14	arm64	Verify current cask name
ai	claude-code-cli	Claude Code CLI	cask	claude-code	no	Anthropic terminal-based coding assistant	homebrew-latest				Use stable Homebrew cask
ai	claude-code-desktop	Claude Code Desktop	cask	claude	no	Claude Desktop app with Claude Code workflows	homebrew-latest				Use official Claude desktop cask
ai	pi-cli	Pi CLI	formula	pi-coding-agent	no	Minimal extensible terminal coding harness	homebrew-latest				Homebrew formula packages the pi.dev CLI
ai	opencode-cli	OpenCode CLI	formula	opencode	no	AI coding agent built for the terminal	homebrew-latest				Homebrew core formula
ai	opencode-desktop	OpenCode Desktop	cask	opencode-desktop	no	Desktop client for the OpenCode coding agent	homebrew-latest				Verify cask name
browser	chrome	Google Chrome	cask	google-chrome	yes	Mainstream browser	homebrew-latest				Verify cask name
browser	firefox	Firefox	cask	firefox	no	Open-source browser	homebrew-latest				Verify cask name
browser	brave	Brave	cask	brave-browser	no	Privacy-focused browser	homebrew-latest				Verify cask name
browser	zen	Zen Browser	cask	zen	no	Gecko-based browser	homebrew-latest				Verify cask name
communication	slack	Slack	cask	slack	no	Team messaging and collaboration app	homebrew-latest				Verify cask name
communication	teams	Microsoft Teams	cask	microsoft-teams	no	Microsoft team chat and video meetings app	homebrew-latest				Verify cask name
runtime	node-npm	Node.js/npm	external	nvm	no	Node.js runtime plus npm package manager	nvm	latest,lts,<node versions>			npm version follows Node unless user opts into npm upgrade
runtime	bun	Bun	external	bun.com/install	no	JavaScript runtime, package manager, and bundler	bun-installer	latest,<bun versions>			Use Homebrew only for latest Homebrew-managed Bun
infra	terraform	Terraform	version-manager	tenv:tf	no	HashiCorp infrastructure-as-code CLI	tenv	latest,<terraform versions>			Avoid disabled Homebrew core formula
infra	opentofu	OpenTofu	version-manager	tenv:tofu	no	Open-source Terraform-compatible IaC CLI	tenv	latest,<opentofu versions>			Managed by tenv
infra	terraspace	Terraspace	tap-formula	boltops-tools/software/terraspace	no	Framework for Terraform/OpenTofu project structure and workflows	homebrew-latest				Specific versions deferred unless RubyGems/Bundler path is added
infra	terragrunt	Terragrunt	version-manager	tenv:tg	no	Wrapper for reusable Terraform/OpenTofu configuration and remote state	tenv	latest,<terragrunt versions>			Managed by tenv
containers	orbstack	OrbStack	cask	orbstack	no	Fast Docker and Linux machine runtime for macOS; requires macOS 14+	homebrew-latest		14		Verify cask name
containers	docker-desktop	Docker Desktop	cask	docker-desktop	no	Docker GUI and runtime bundle for macOS; requires macOS 14+	homebrew-latest		14		Verify current cask name
containers	docker-cli	Docker CLI	formula	docker	no	Standalone Docker command-line client	homebrew-latest				Verify formula name
```

Before implementation, actual Homebrew formula/cask names and external installer sources should be verified with `brew info`, `brew info --cask`, official package-manager metadata, or the vendor's official installation docs because package names and distribution methods can change. Items that cannot be installed automatically and safely should not pretend to be installable; they should be disabled with a clear reason or omitted until a supported installer is available.

## macOS Preferences (Minimal, Opt-In)

macOS stores most settings in a database changed via `defaults write` (and `killall Finder`/`killall Dock` to apply). v1 includes a small, safe, clearly-labeled, opt-in set only — never applied silently. Candidate tweaks:

- Finder: show hidden files, show file extensions, show full path in title bar.
- Dock: auto-hide, adjust size.
- Keyboard: faster key-repeat rate (popular with developers).
- Screenshots: change save location (e.g. `~/Screenshots`) and/or format.

Anything that changes deeper system behavior is deferred. Every tweak must be explicitly chosen by the user, and the chosen tweaks are written to the re-runnable `macos-defaults.sh` described under Reproducibility.

The macOS defaults catalog is structured as:

```text
id	label	description	domain	key	type	value	restart_hint
```

v1 supports `type=bool` with `value=true|false`. `rig` renders these rows from
fixed `defaults write '<domain>' '<key>' -bool <value>` templates plus the
allowlisted Finder/Dock restart commands.

## Self-Update

The tool lives locally after the first run, preferably under:

```text
~/.local/share/rig
```

The command is exposed as:

```text
~/.local/bin/rig
```

Recommended user-facing commands:

```text
rig install
rig install --dry-run
rig install --yes --select gh
rig dry-run
rig list
rig doctor
rig self-update
rig update-tools
rig version
```

`rig self-update` updates only the bootstrap tool itself, normally by running a
fast-forward-only Git pull in the local clone. Before fetching, it verifies the
clone `origin` against the trusted origin recorded by bootstrap, falling back
to the default public GitHub repository for existing pre-record clones.
`rig update-tools` updates installed packages separately through Homebrew.

Keeping these separate avoids surprising users. Updating the installer script and upgrading all workstation software are different operations.

## Auto-Update Options

`rig` always asks before enabling any automatic Homebrew updates, and the **default is OFF**. Many DevOps engineers do not want surprise upgrades of Terraform, cloud CLIs, Kubernetes tools, or container runtimes during active work.

When the user opts in, there are two reasonable approaches:

1. Use the `homebrew-autoupdate` command.
2. Generate a custom macOS LaunchAgent that runs selected Homebrew commands.

`homebrew-autoupdate` uses `launchd`, runs `brew update` in the background on a schedule, and can optionally run `brew upgrade` and `brew cleanup`. Its README documents options such as `--upgrade`, `--cleanup`, `--immediate`, and custom intervals.

A custom LaunchAgent gives more control and fewer external moving parts. Apple documents user LaunchAgents under the user's `~/Library/LaunchAgents` directory and supports scheduled starts with keys such as `RunAtLoad`, `StartInterval`, and `StartCalendarInterval`.

## Mac App Store Apps

The `mas` CLI can install and update Mac App Store apps from the terminal and is designed for scripting. However, it has practical limitations:

- The user must be signed into the Mac App Store.
- Some apps must already be associated with the user's Apple ID.
- Apple may require authentication or GUI interaction.

Mac App Store support is optional in v1. The tool does not depend on `mas` for core setup.

## macOS Automation Limits

Some setup steps cannot be fully automated by a normal shell script:

- Apple ID sign-in.
- App Store authentication.
- Privacy and security permissions.
- Screen recording, accessibility, automation, full disk access, and similar TCC prompts.
- Some app-specific first-run configuration.
- Company policy enforcement without MDM.

For personal/public use, `rig` guides the user and automates the installable parts. Company-managed Macs would need MDM, configuration profiles, Apple Business Manager, and device-management policies — out of scope here.

## Recommended v1 Scope

Build v1 as a polished public interactive bootstrap tool, not an enterprise provisioning system.

Include:

- macOS-only guard.
- Bash 3.2-compatible runtime; Zsh/Bash login-shell handling.
- Homebrew install/detection.
- Category-based installer.
- Data-driven TSV catalog.
- Required short descriptions for every selectable catalog item.
- AI tools category with Codex CLI, Codex Desktop, Claude Code CLI, Claude Desktop / Claude Code desktop workflow, Pi Coding Agent, and OpenCode.
- Selectable Node.js/npm and Bun install choices with version prompts where the chosen install strategy supports version selection.
- `nvm`-backed Node.js/npm version management.
- `tenv`-backed Terraform, OpenTofu, and Terragrunt version management.
- Selectable infrastructure-as-code tools: Terraform, OpenTofu, Terraspace, and Terragrunt.
- `gum` UI with Bash fallback.
- Brewfile generation from selected choices.
- External install-plan generation for selected tools that are not Brewfile-native.
- Committable Brewfile + external install plan + macOS preferences script for reproducibility.
- Non-interactive mode (flags / existing rig config / bring-your-own Brewfile or install plan).
- Dry-run simulation mode that makes no package, shell, config, defaults, LaunchAgent, or other system/user changes.
- Minimal opt-in macOS preferences.
- Self-update command.
- Doctor/diagnostics command.
- Optional Homebrew update automation (ask, default OFF).
- Clear README with the one-line install command.

Defer:

- MDM support.
- Fully silent enterprise installs.
- Secrets management.
- Complex app preference synchronization.
- Cross-platform Linux support.
- Homebrew tap distribution.
- GUI application beyond terminal prompts.

## Sources

- Homebrew: https://brew.sh/
- Homebrew installation docs: https://docs.brew.sh/Installation
- Homebrew Bundle and Brewfile docs: https://docs.brew.sh/Brew-Bundle-and-Brewfile
- Homebrew manpage: https://docs.brew.sh/Manpage.html
- Homebrew autoupdate: https://github.com/DomT4/homebrew-autoupdate
- Apple launchd LaunchAgents documentation: https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html
- mas CLI: https://github.com/mas-cli/mas
- gum interactive shell prompts: https://github.com/charmbracelet/gum
- macOS default shell change to Zsh / bundled /bin/bash 3.2.57: https://jmmv.dev/2019/11/macos-bash-baggage.html
- Codex CLI Homebrew cask: https://formulae.brew.sh/cask/codex
- Codex Desktop Homebrew cask: https://formulae.brew.sh/cask/codex-app
- Claude Code setup docs: https://code.claude.com/docs/en/setup
- Claude Code Homebrew cask: https://formulae.brew.sh/cask/claude-code
- Claude Desktop Homebrew cask: https://formulae.brew.sh/cask/claude
- Pi Coding Agent: https://pi.dev/
- OpenCode: https://github.com/opencode-ai/opencode
- tenv version manager: https://github.com/tofuutils/tenv
- tfenv Terraform version manager: https://github.com/tfutils/tfenv
- tofuenv OpenTofu version manager: https://github.com/tofuutils/tofuenv
- nvm Node.js version manager: https://github.com/nvm-sh/nvm
- npm Node.js/npm install guidance: https://docs.npmjs.com/downloading-and-installing-node-js-and-npm/
- Bun installation docs: https://bun.sh/docs/installation
- Terraform official install docs: https://developer.hashicorp.com/terraform/intro/getting-started/install.html
- Terraspace macOS install docs: https://terraspace.cloud/docs/install/standalone/macosx/
