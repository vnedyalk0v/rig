# Repository Settings

Inspected on 2026-06-02 for `vnedyalk0v/rig`.

This document records the current GitHub repository settings that were visible
through the GitHub API and the recommended settings for a fresh public
open-source repository.

## Current State

- Visibility: public.
- Default branch: `main`.
- License: MIT.
- Issues: enabled.
- Pull requests: enabled.
- Projects: enabled.
- Wiki: enabled.
- Discussions: disabled.
- Pages: disabled.
- Merge methods: squash, merge commit, and rebase are enabled.
- Auto-merge: disabled.
- Delete branch on merge: disabled.
- Actions: enabled with all actions allowed.
- Secret scanning: enabled.
- Secret scanning push protection: enabled.
- Dependabot security updates: disabled.
- Dependabot vulnerability alerts: disabled.
- Community profile health: 42%.
- Community files detected: `README.md` and `LICENSE`.
- Missing community files: `CONTRIBUTING.md`, `SECURITY.md`,
  `CODE_OF_CONDUCT.md`, issue templates, and pull request template.
- Active repository ruleset: `Protect main`.

## Ruleset Finding

The repository has an active branch ruleset named `Protect main`, but the ruleset
condition returned by the API is:

```text
refs/heads/"main"
```

The branch endpoint still reports `main` as not protected. The recommended fix
is to update the ruleset condition to:

```text
refs/heads/main
```

Keep the useful existing rules:

- prevent branch deletion;
- prevent non-fast-forward updates;
- require pull requests;
- require review thread resolution;
- allow only squash merges.

For a solo-maintained fresh repo, zero required approvals is acceptable until
there are collaborators or required status checks. Once CI exists, add required
status checks before merging into `main`.

## Recommended Settings

These changes should be approved and applied in explicit setting groups.

### Repository Features

- Keep Issues enabled.
- Keep Pull Requests enabled.
- Keep Discussions disabled until there is an active community need.
- Disable Wiki unless it becomes intentionally maintained.
- Disable Projects unless there is an active board.
- Enable automatic deletion of merged branches.

Rationale: a fresh project should keep contributors focused on the README,
issues, and pull requests instead of splitting documentation across an
unmaintained wiki or unused project board.

### Merge Policy

- Enable squash merge.
- Disable merge commits.
- Disable rebase merge.
- Keep auto-merge disabled until CI exists.
- Use pull requests for `main`.

Rationale: squash-only merges keep public history readable and match the current
ruleset's allowed merge method.

### Security And Analysis

- Keep secret scanning enabled.
- Keep secret scanning push protection enabled.
- Enable Dependabot alerts.
- Enable Dependabot security updates.
- Enable non-provider secret patterns and validity checks if GitHub exposes them
  for this repository.
- Enable private vulnerability reporting if available.

Rationale: `rig` will execute installer code and orchestrate third-party tools,
so security reporting and dependency visibility should be enabled early.

### Actions

- Keep Actions enabled.
- Prefer GitHub-owned or verified actions.
- Add workflows only after implementation code exists.
- Add required status checks to the `main` ruleset only after those checks exist.
- Pin third-party actions by SHA when workflows grow beyond simple trusted
  actions.

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
