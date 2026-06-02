## Summary

- Describe the change in one or two bullets.

## Checklist

- [ ] Base branch is `dev` (only `dev` or `hotfix/*` may target `main`).
- [ ] Branch name uses a repo prefix (`feat/`, `fix/`, `bug/`, `docs/`,
      `chore/`, `ci/`, or `refactor/`) unless this is the `main -> dev` sync.
- [ ] PR title starts with `feat:`, `fix:`, `bug:`, `docs:`, `chore:`, `ci:`,
      or `refactor:`.
- [ ] The change matches `docs/rig-v1-spec.md` or updates the spec.
- [ ] User-facing behavior is documented.
- [ ] Security-sensitive behavior is documented or called out.
- [ ] Dry-run behavior remains side-effect free.
- [ ] Shell code that runs on a clean Mac is Bash 3.2-compatible.
- [ ] Shell/config edits are idempotent.

## Validation

```bash
# Add the exact commands you ran.
```

## Security Impact

Describe whether this changes installer behavior, external installer handling,
shell configuration, generated files, macOS defaults, or update behavior.
