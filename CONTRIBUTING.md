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

## Pull Request Checklist

Before opening a pull request, confirm:

- [ ] The change matches `docs/rig-v1-spec.md` or updates the spec.
- [ ] User-facing behavior is documented in `README.md` or another linked doc.
- [ ] Security-sensitive behavior is covered in `SECURITY.md` when relevant.
- [ ] Dry-run behavior is preserved or explicitly improved.
- [ ] Shell code is compatible with `/bin/bash` 3.2 when it runs before tool
      installation.
- [ ] Generated shell/config edits are idempotent.

## Validation

No implementation test suite exists yet. Once scripts are added, changes should
include focused validation such as:

```bash
bash -n install.sh
bash -n path/to/script.sh
./install.sh --dry-run
./rig dry-run
```

Catalog changes should also be validated by a command or script that proves the
TSV shape is parseable and every selectable item has a description.

## Issues

Use the issue templates when possible. Please keep security-sensitive reports
out of public issues; see [SECURITY.md](SECURITY.md).
