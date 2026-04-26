## Why

Agent runs are currently failing for `claude_cli_stream` with `ArgumentError` even though the backend module implements the required callbacks. The failure happens because callback validation checks exported functions before ensuring the backend module is loaded, which causes false negatives and repeated backoff retries.

## What Changes

- Update backend callback validation so resolved backend modules are explicitly loaded before `function_exported?/3` checks run.
- Define deterministic behavior when a backend module cannot be loaded versus when it loads but does not satisfy the `AgentBackend` callback contract.
- Add regression coverage for backend validation paths, including unloaded-but-valid modules and invalid backend modules.
- Improve error reporting for backend validation failures so operators can quickly distinguish loading failures from interface mismatch failures.

## Capabilities

### New Capabilities
- `agent-backend-module-validation`: Ensures backend module validation is load-aware and reliably enforces the `AgentBackend` callback contract.

### Modified Capabilities
- None.

## Impact

- Affected code: `elixir/lib/symphony_elixir/agent_runner.ex`, backend validation logic, and related tests under `elixir/test/symphony_elixir/`.
- Operational impact: prevents false `ArgumentError` crashes and retry storms for valid backends like `claude_cli_stream`.
- No external API changes expected.
