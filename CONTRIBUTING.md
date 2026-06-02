# Contributing

Thanks for helping improve `rig`. This project is currently pre-release, so
contributions should stay close to the v1 specification in
[docs/rig-v1-spec.md](docs/rig-v1-spec.md).

## Project Direction

`rig` is a public open-source macOS bootstrap tool, not an enterprise
provisioning system. v1 should remain small, auditable, and practical for a
clean Mac.

Preferred contributions:

- small pull requests with one clear purpose;
- changes that improve the v1 spec, docs, installer safety, catalog behavior,
  or dry-run behavior;
- explicit handling for macOS, Bash 3.2, Homebrew, and shell startup files;
- clear docs updates for user-facing behavior.

Out of scope for v1:

- Linux support;
- MDM or enterprise fleet management;
- secrets management;
- GUI app preference synchronization;
- complex profile systems.

## Development Rules

- Keep the bootstrap entrypoint readable and small.
- Preserve Bash 3.2 compatibility for scripts that must run on a clean macOS
  install.
- Prefer Homebrew Bundle for Homebrew-native packages.
- Use explicit version managers or vendor installers only when Homebrew cannot
  provide the required version behavior.
- Make shell configuration edits idempotent with managed markers.
- Keep dry-run paths side-effect free.
- Require short descriptions for catalog items.
- Do not silently install everything by default.

## Branching and Pull Request Workflow

`rig` uses two long-lived branches:

- `dev` — the default integration branch. All everyday work targets `dev`.
- `main` — the stable release branch. The one-line install command runs
  `install.sh` from `main`, so `main` must always be in a known-good state.

The workflow is:

1. Branch off `dev` (for example `feat/catalog-tsv` or `fix/shell-detection`).
2. Open your pull request against `dev`. **Never open a feature pull request
   directly against `main`** — a CI check rejects it.
3. A maintainer promotes `dev` to `main` with a `dev` -> `main` pull request.
4. Emergency fixes may use a `hotfix/*` branch that targets `main` directly.

Pull requests into `main` are only accepted from `dev` or `hotfix/*` and only
from this repository; this is enforced by the `verify-base` GitHub Actions
check (`.github/workflows/pr-base-guard.yml`).

Merge methods: feature pull requests are **squash-merged** into `dev`, while
`dev <-> main` promotions and back-merges are **merge-committed** so the two
long-lived branches keep a shared ancestor (squash-promoting between them
creates phantom conflicts).

### Keeping `dev` in sync after a hotfix

A `hotfix/*` branch lands on `main` without going through `dev`, so `dev` would
be missing that fix. This is handled automatically: the `sync-main-to-dev`
workflow (`.github/workflows/sync-main-to-dev.yml`) runs on every push to
`main` and, whenever `main` and `dev` differ in content, opens a
`main -> dev` back-merge pull request titled `chore: sync main into dev`. The
maintainer reviews and **merge-commits** it (not squash) to realign the
branches while preserving their shared ancestor.

Normal `dev -> main` promotions leave both branches with identical content, so
no sync pull request is opened in that case. `dev` is protected, so the realign
always happens through that pull request (merge-commit it) rather than a direct
push; you can open it manually if needed with
`gh pr create --base dev --head main`.

[CodeRabbit](https://coderabbit.ai) reviews every pull request automatically
using `.coderabbit.yaml`. Address its findings, or reply explaining why a
suggestion does not apply, before requesting a merge.

## Pull Request Checklist

Before opening a pull request, confirm:

- [ ] The pull request targets `dev` (or `main` only for a `dev`/`hotfix/*` branch).
- [ ] The change matches `docs/rig-v1-spec.md` or updates the spec.
- [ ] User-facing behavior is documented in `README.md` or another linked doc.
- [ ] Security-sensitive behavior is covered in `SECURITY.md` when relevant.
- [ ] Dry-run behavior is preserved or explicitly improved.
- [ ] Shell code is compatible with `/bin/bash` 3.2 when it runs before tool
      installation.
- [ ] Generated shell/config edits are idempotent.

## Validation

There is no build system. Use the shell test harness and focused syntax checks:

```bash
bash tests/run-tests.sh
for f in install.sh rig lib/rig/*.sh scripts/validate-catalog.sh tests/run-tests.sh; do
  bash -n "$f"
done
./install.sh --dry-run
./rig dry-run
```

Catalog changes should also be validated by a command or script that proves the
TSV shape is parseable and every selectable item has a description.

```bash
./scripts/validate-catalog.sh
```

## Issues

Use the issue templates when possible. Please keep security-sensitive reports
out of public issues; see [SECURITY.md](SECURITY.md).
