# Repository Settings

Inspected on 2026-06-02 for `vnedyalk0v/rig`, then updated to record the branch
workflow and review tooling that were configured for the repository.

This document records the configured GitHub repository settings and the
rationale for a public open-source repository.

## Current State

- Visibility: public.
- Default branch: `dev`.
- Branches: `dev` (default integration branch) and `main` (stable release
  branch; the install one-liner runs `install.sh` from `main`).
- License: MIT.
- Issues: enabled.
- Pull requests: enabled.
- Projects: disabled.
- Wiki: disabled.
- Discussions: disabled.
- Pages: disabled.
- Merge methods: squash only (merge commits and rebase merges disabled).
- Auto-merge: disabled.
- Delete branch on merge: enabled.
- Actions: enabled with all actions allowed.
- Secret scanning: enabled.
- Secret scanning push protection: enabled.
- Dependabot security updates: enabled.
- Dependabot vulnerability alerts: enabled.
- Code review: CodeRabbit (free Open Source plan) reviews every pull request
  using `.coderabbit.yaml`.
- Community profile health: 100%.
- Community files present: `README.md`, `LICENSE`, `CONTRIBUTING.md`,
  `SECURITY.md`, `CODE_OF_CONDUCT.md`, `SUPPORT.md`, issue templates under
  `.github/ISSUE_TEMPLATE/`, and `.github/pull_request_template.md`.
- Active repository rulesets: `Protect main` and `Protect dev`.

## Branch Protection and Workflow

Work flows `feature/* -> dev -> main`. Feature branches target `dev`; the
maintainer promotes `dev` to `main`. Emergency `hotfix/*` branches may target
`main` directly, after which `main` is synced back into `dev`.

GitHub rulesets cannot restrict the source branch of a pull request, so the
"only `dev` (or `hotfix/*`) may target `main`" rule is enforced by the
`verify-base` GitHub Actions check in `.github/workflows/pr-base-guard.yml`,
which is a required status check on `main`. It also rejects pull requests whose
head repository is not this repository, so a fork branch named `dev` cannot
bypass it.

The earlier `Protect main` ruleset condition bug was fixed: the condition is now
`refs/heads/main` (previously the API reported `refs/heads/"main"`, which left
`main` effectively unprotected).

`Protect main` rules:

- prevent branch deletion;
- prevent non-fast-forward updates;
- require pull requests;
- require review thread resolution;
- require the `verify-base` status check;
- allow only squash merges.

`Protect dev` rules:

- prevent branch deletion;
- prevent non-fast-forward updates;
- require pull requests;
- allow only squash merges.

For a solo-maintained repo, zero required approvals is acceptable until there
are collaborators.

## Applied Settings

These setting groups were applied to the repository.

### Repository Features

- Issues enabled.
- Pull Requests enabled.
- Discussions disabled until there is an active community need.
- Wiki disabled.
- Projects disabled.
- Automatic deletion of merged branches enabled.

Rationale: a fresh project should keep contributors focused on the README,
issues, and pull requests instead of splitting documentation across an
unmaintained wiki or unused project board.

### Merge Policy

- Squash merge enabled.
- Merge commits disabled.
- Rebase merge disabled.
- Auto-merge disabled.
- Pull requests required for `main` and `dev`.

Rationale: squash-only merges keep public history readable and match the
rulesets' allowed merge method.

### Security And Analysis

- Secret scanning enabled.
- Secret scanning push protection enabled.
- Dependabot alerts enabled.
- Dependabot security updates enabled.
- Enable non-provider secret patterns and validity checks if GitHub exposes them
  for this repository.
- Enable private vulnerability reporting if available.

Rationale: `rig` will execute installer code and orchestrate third-party tools,
so security reporting and dependency visibility should be enabled early.

### Actions

- Actions enabled.
- Prefer GitHub-owned or verified actions.
- The `verify-base` workflow is a required status check on `main` (added after
  it ran once on a `dev` -> `main` pull request).
- Pin third-party actions by SHA when workflows grow beyond simple trusted
  actions. The current `pr-base-guard.yml` workflow uses no third-party actions.

Rationale: required checks are useful only after workflows exist; enabling them
too early can block all merges.

## Suggested GitHub API Checks

Re-check the repository state with:

```bash
gh api repos/vnedyalk0v/rig
gh api repos/vnedyalk0v/rig/community/profile
gh api repos/vnedyalk0v/rig/rulesets
gh api repos/vnedyalk0v/rig/rulesets/<ruleset-id>
gh api repos/vnedyalk0v/rig/vulnerability-alerts
```

The `vulnerability-alerts` endpoint returns HTTP 204 when alerts are enabled and
HTTP 404 when they are disabled or unavailable to the caller.

## Source References

- GitHub community profile docs:
  <https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/about-community-profiles-for-public-repositories>
- GitHub contributing guidelines docs:
  <https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/setting-guidelines-for-repository-contributors>
- GitHub merge methods docs:
  <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/about-merge-methods-on-github>
- GitHub automatic branch deletion docs:
  <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-the-automatic-deletion-of-branches>
- GitHub Dependabot alerts docs:
  <https://docs.github.com/en/code-security/dependabot/dependabot-alerts/about-dependabot-alerts>
- GitHub Dependabot security updates docs:
  <https://docs.github.com/code-security/dependabot/dependabot-security-updates/configuring-dependabot-security-updates>
