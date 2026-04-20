## ADDED Requirements

### Requirement: Required repo-local skills are listed as prerequisites
`elixir/README.md` SHALL state that `commit`, `push`, `pull`, `land`, and `linear` are required prerequisites for using Symphony in a repository, and SHALL not describe that step as optional.

#### Scenario: User follows setup instructions
- **WHEN** a user reads the setup steps in `elixir/README.md`
- **THEN** the skill-copy step is presented as required before use

#### Scenario: User checks the prerequisite list
- **WHEN** a user scans the setup checklist
- **THEN** the five required skills are explicitly listed

### Requirement: The linear skill dependency remains explicit
`elixir/README.md` SHALL explain that the `linear` skill depends on Symphony's `linear_graphql` app-server tool for raw Linear GraphQL operations.

#### Scenario: User prepares the linear skill
- **WHEN** a user reads the note under the required skills step
- **THEN** the documentation explains the `linear_graphql` dependency
