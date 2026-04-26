## 1. Backend Validation Logic

- [ ] 1.1 Update `AgentRunner` backend validation to ensure the resolved backend module is loaded before callback export checks.
- [ ] 1.2 Implement differentiated error handling/messages for module load failure versus callback-contract mismatch.
- [ ] 1.3 Keep existing callback contract enforcement for `start_session/2`, `run_turn/3`, and `stop_session/1`.

## 2. Regression Test Coverage

- [ ] 2.1 Add or update `agent_runner` tests to cover a valid backend module that is not preloaded at validation time.
- [ ] 2.2 Add or update tests for backend module load failure behavior and assert it is distinguishable from callback mismatch.
- [ ] 2.3 Add or update tests for loaded modules missing required callbacks and assert contract failure semantics.

## 3. Verification

- [ ] 3.1 Run targeted Elixir tests for backend validation and `AgentRunner` paths.
- [ ] 3.2 Confirm no behavior regression for existing valid backend resolution paths.
- [ ] 3.3 Document verification outcomes in the implementation workpad or PR notes.
