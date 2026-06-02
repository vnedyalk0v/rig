# rig MVP Evaluation - 2026-06-02

## Current Status

No unresolved MVP findings remain from this audit after the remediation pass.

The original evaluation identified five fixable issues: macOS guard bypasses,
repeated selection flag overrides, missing `gh pr` repository context in the
`main -> dev` sync workflow, unknown category filters rendering empty successful
plans, and bootstrap command-path conflict checks running after clone/update
work. Those items have been fixed and removed from the open findings list.

## Remaining Findings

None.

## Deferred Or False-Positive Items

- The tiny catalog is not a defect in this MVP. The v1 breadth in the spec is
  deferred until real install strategy work starts.
- Missing interactive prompts, `gum`, config replay, generated `Brewfile`,
  external install plan files, and generated `macos-defaults.sh` are deferred by
  the documented MVP status.
- Rejection of whitespace inside `--select 'vscode, chrome'` is not treated as a
  current defect because the CLI documents comma-separated IDs, and the
  interactive plain-Bash space/comma input path is not implemented yet.
- Current workflows have no third-party actions to pin and do not check out PR
  code for policy enforcement.

## Verification Notes

Regression coverage now asserts:

- non-Darwin `install.sh --dry-run`, `rig dry-run`, `rig install --dry-run`, and
  `rig self-update` fail before rendering plans or invoking `git`;
- repeated `--select`, `--defaults`, and `--category` flags fail clearly;
- unknown categories fail for `rig list` and `rig dry-run`;
- `sync-main-to-dev.yml` passes `--repo "$REPO"` to `gh pr list` and
  `gh pr create`;
- bootstrap command-path conflicts fail before any `git clone`, `git fetch`, or
  `git pull` invocation.
