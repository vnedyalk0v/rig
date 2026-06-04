# Codex Security Scan Findings - 2026-06-04

This audit records the reportable findings from a repository-wide Codex
Security scan of `rig`.

## Scan Metadata

| Field | Value |
|---|---|
| Target | `/Users/vnedyalk0v/Projects/Personal/rig` |
| Scan mode | Repository-wide Codex Security scan |
| Commit | `7b4b979ad327e987c7bfa30b6e3c6a98733850c9` |
| Branch state at scan time | `ci/apple-silicon-smoke...origin/ci/apple-silicon-smoke` |
| Source scan bundle | `/tmp/codex-security-scans/rig/7b4b979ad327_20260604T093905Z` |
| Source report | `/tmp/codex-security-scans/rig/7b4b979ad327_20260604T093905Z/report.md` |
| Validation mode | Full-file source review plus bounded local PoCs under disposable paths |
| Repository mutations during scan | None |

## Summary

| ID | Finding | Severity | Confidence | Status |
|---|---|---|---|---|
| `RIG-SEC-001` | Existing local clone state can redirect bootstrap/self-update to untrusted code | Medium | High | Fixed |
| `RIG-SEC-002` | Tool catalog fields can inject Ruby interpolation into generated Brewfile | Medium | High | Fixed |
| `RIG-SEC-003` | macOS defaults catalog command field is emitted verbatim into an executed shell script | Medium | High | Fixed |

## RIG-SEC-001: Existing Local Clone State Can Redirect Bootstrap/Self-Update To Untrusted Code

| Field | Value |
|---|---|
| Severity | Medium |
| Confidence | High |
| Category | Supply-chain/update-channel provenance validation failure |
| CWE | CWE-494: Download of Code Without Integrity Check; CWE-829: Inclusion of Functionality from Untrusted Control Sphere |
| Affected lines | `install.sh:147-153`, `install.sh:167-169`, `rig:67-70` |

### Summary

When `install.sh` finds an existing `~/.local/share/rig` clone, it updates that
clone from its current `origin` and then executes `~/.local/bin/rig install`.
The fresh-clone path validates `--repo-url`, but the existing-clone path does
not validate `remote.origin.url` or otherwise bind the clone to the
requested/default repository before pulling and executing the updated command.

`rig self-update` has the same provenance problem by code trace: it fetches and
pulls the current local clone origin without first verifying that origin against
the expected repository.

### Validation Evidence

A disposable-HOME proof of concept created `HOME/.local/share/rig` as a real
Git clone whose `origin` pointed at a local malicious repository that would not
pass the fresh-clone `--repo-url` validator. Running the checked-out
`install.sh` with a fake Darwin `uname` fast-forwarded that clone and executed
the malicious `rig install`, producing a marker with:

```text
MALICIOUS_RIG_EXECUTED args=install
```

Validation artifacts:

- `artifacts/05_findings/RIG-SEC-001/validation_report.md`
- `artifacts/05_findings/RIG-SEC-001/validation_artifacts/reproduce_existing_clone_origin.sh`
- `artifacts/05_findings/RIG-SEC-001/validation_artifacts/poc_run.Sto5PW/proof-summary.txt`

### Impact And Reachability

This is a local supply-chain update path, not a public network listener. The
attacker needs existing local clone state to be influenced, for example through
a prior custom bootstrap source or same-user tampering. The meaningful boundary
is provenance: a user can run the reviewed/default bootstrap entrypoint while
the existing clone is updated and executed from a different, unvalidated source.

### Recommended Fix

- Before updating an existing clone, compare
  `git -C "$install_root" remote get-url origin` with the requested/default
  `repo_url`.
- Refuse, warn, or require explicit confirmation when the existing origin
  differs.
- Apply equivalent origin/provenance validation in `rig self-update`.
- Add regression tests for existing-clone origin mismatch, custom-origin opt-in
  behavior, and self-update origin validation.

### Fix Status

Fixed in the working tree. `install.sh` now canonicalizes GitHub HTTPS/SSH
origins, refuses existing-clone origin mismatches before `git fetch` or local
`rig` execution, and records the trusted origin in local git config.
`rig self-update` validates the current clone origin against that trusted origin
before fetching or pulling.

Regression coverage in `tests/run-tests.sh` proves mismatched origins do not
fetch or execute, and canonical HTTPS/SSH matches still update normally.

## RIG-SEC-002: Tool Catalog Fields Can Inject Ruby Interpolation Into Generated Brewfile

| Field | Value |
|---|---|
| Severity | Medium |
| Confidence | High |
| Category | Brewfile DSL injection / interpreter injection |
| CWE | CWE-94: Improper Control of Generation of Code; CWE-78: OS Command Injection |
| Affected lines | `lib/rig/catalog.sh:5-10`, `lib/rig/catalog.sh:182`, `lib/rig/common.sh:79-93`, `lib/rig/plan.sh:289`, `lib/rig/plan.sh:292`, `lib/rig/plan.sh:295`, `lib/rig/plan.sh:298`, `lib/rig/plan.sh:303`, `lib/rig/brew.sh:141` |

### Summary

Tool catalog fields are rendered into generated Brewfile lines using Ruby
double-quoted strings. `rig_escape_brew_string` escapes backslashes and double
quotes, but it does not neutralize Ruby interpolation syntax such as `#{...}`.
A catalog-controlled package or label can therefore execute Ruby code when
Homebrew Bundle evaluates the generated Brewfile.

### Validation Evidence

Validation created a malicious `RIG_TOOLS_CATALOG` with a selected `formula`
package value containing Ruby interpolation. `./rig install --write-config-only
--select evil-brew` emitted a Brewfile containing the interpolation.

Running:

```bash
HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file=<generated Brewfile>
```

evaluated the Brewfile and wrote the marker file. No packages were installed.

Validation artifacts:

- `artifacts/05_findings/RIG-SEC-002/validation_report.md`
- `artifacts/05_findings/RIG-SEC-002/validation_artifacts/malicious_tools.tsv`
- `artifacts/05_findings/RIG-SEC-002/validation_artifacts/generated_Brewfile`
- `artifacts/05_findings/RIG-SEC-002/validation_artifacts/brew_bundle_check.log`
- `artifacts/05_findings/RIG-SEC-002/validation_artifacts/ruby_interpolation_marker.txt`

### Impact And Reachability

This is a local supply-chain catalog path rather than an internet-exposed
service. The attacker must influence the active tools catalog or get a
malicious package/label row accepted into a catalog used by the victim. The
checked-in catalog is benign, but validation proves the data-to-code boundary
crossing when Homebrew Bundle evaluates the generated Brewfile.

### Recommended Fix

- Generate Brewfile entries using non-interpolating Ruby string forms, or
  correctly escape interpolation-sensitive content.
- Add strict package/label validation for Brewfile-native kinds: `formula`,
  `cask`, `tap`, `vscode`, and `mas` labels.
- Add regression tests for `#{...}` in catalog `package` and `label` fields.
- Decide whether `RIG_TOOLS_CATALOG` is a supported user extension point or a
  test-only/internal hook, then document and enforce that policy.

### Fix Status

Fixed in the working tree. Brewfile entries are generated with
non-interpolating Ruby single-quoted strings, and catalog validation rejects
Brewfile-native package values containing interpolation or invalid package
characters. `tap-formula` rows are validated as strict tap owner/name/formula
segments, and `mas` labels are checked before rendering.

Regression coverage in `tests/run-tests.sh` proves `#{...}` package payloads are
rejected and generated Brewfile previews use non-interpolating strings.

## RIG-SEC-003: macOS Defaults Catalog Command Field Is Emitted Verbatim Into An Executed Shell Script

| Field | Value |
|---|---|
| Severity | Medium |
| Confidence | High |
| Category | Command injection / unsafe shell generation |
| CWE | CWE-78: OS Command Injection |
| Affected lines | `lib/rig/catalog.sh:223-243`, `lib/rig/catalog.sh:239`, `lib/rig/plan.sh:361-376`, `lib/rig/plan.sh:691-709`, `lib/rig/apply.sh:147-156` |

### Summary

The macOS defaults catalog stores shell command text, and validation only
requires that command field to be non-empty. `rig_emit_macos_defaults` prints
that text verbatim into generated `macos-defaults.sh`, and
`rig_apply_macos_defaults` executes the generated script with Bash. A malicious
defaults catalog row can therefore run arbitrary user-level shell commands
during config replay.

### Validation Evidence

Validation created a malicious `RIG_DEFAULTS_CATALOG` row whose command wrote a
marker file. `./rig install --write-config-only --defaults evil-default`
generated `macos-defaults.sh` containing that command verbatim. `./rig install
--from-config` executed the generated script and created the marker. A fake
`brew` shim and a non-default tools catalog prevented package installation from
entering the proof.

Validation artifacts:

- `artifacts/05_findings/RIG-SEC-003/validation_report.md`
- `artifacts/05_findings/RIG-SEC-003/validation_artifacts/cli-repro-20260604T095616Z-80208/malicious-macos-defaults.tsv`
- `artifacts/05_findings/RIG-SEC-003/validation_artifacts/cli-repro-20260604T095616Z-80208/generated-macos-defaults.sh`
- `artifacts/05_findings/RIG-SEC-003/validation_artifacts/cli-repro-20260604T095616Z-80208/RIG-SEC-003-marker.txt`

### Impact And Reachability

This is a local supply-chain catalog path. The attacker must influence the
defaults catalog path/content or get a malicious defaults row into a catalog
consumed by the user. The default checked-in defaults catalog contains benign
`defaults write` rows, and there is no public remote catalog fetch. The issue
remains in scope because generated defaults scripts and catalog handling are
explicitly security-sensitive surfaces.

### Recommended Fix

- Replace raw shell commands in `catalog/macos-defaults.tsv` with a structured,
  allowlisted schema such as domain, key, type, and value.
- Generate shell from fixed templates with quoted structured values.
- Reject arbitrary shell metacharacters or non-`defaults write` command shapes
  if raw command storage remains temporarily necessary.
- Add tests proving malicious defaults command payloads are rejected and
  generated scripts contain only allowlisted commands.

### Fix Status

Fixed in the working tree. `catalog/macos-defaults.tsv` now stores structured
`domain`, `key`, `type`, and `value` fields instead of raw shell commands. v1
supports only boolean defaults rows and renders them from a fixed
`defaults write '<domain>' '<key>' -bool <value>` template. Saved
`macos-defaults.sh` replay validates every line before invoking Bash, allowing
only generated defaults commands and Finder/Dock restart lines.

Regression coverage in `tests/run-tests.sh` proves raw-command defaults
catalogs are rejected and tampered saved defaults scripts fail without executing
their payload.

## Follow-Up

- The implemented policy is strict by default: custom bootstrap origins require
  an explicit `--repo-url` and later updates require matching persisted
  provenance; custom catalog paths remain internal/test hooks unless a future
  feature documents them as public extension points.
- The full local gate from `AGENTS.md` plus focused regression coverage for
  these three findings was rerun after the fixes in this working tree.
