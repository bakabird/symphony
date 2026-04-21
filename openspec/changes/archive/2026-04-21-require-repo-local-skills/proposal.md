## Why

`elixir/README.md` currently describes copying the `commit`, `push`, `pull`, `land`, and `linear` skills as optional, but Symphony's workflow assumes those repo-local capabilities exist before a user can complete PR creation, review sweep, and merge handling. That mismatch makes the setup guidance look softer than the actual operational requirement.

## What Changes

- Change the setup instructions in `elixir/README.md` so copying the repo-local skills is required, not optional.
- Clarify that the required skills are `commit`, `push`, `pull`, `land`, and `linear`.
- Keep the note that the `linear` skill depends on Symphony's `linear_graphql` app-server tool.
- **BREAKING**: the repository setup guide will no longer present repo-local skills as skippable.

## Capabilities

### New Capabilities
- `repo-local-skills-required`: repository setup guidance requires the repo-local Codex skills needed for commit, push, pull, review, and merge workflows.

### Modified Capabilities
- None

## Impact

- Affects `elixir/README.md` setup guidance and the wording of the repository bootstrap path.
- Aligns the written prerequisites with the workflow's actual dependency on repo-local skills.
- Does not change runtime code, tracker APIs, or workflow execution logic.
