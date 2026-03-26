# Railsmith Implementation Phases (Small Batches)

This file breaks the roadmap into small implementation and testing phases so each phase can be completed and verified independently.

## Phase 0 - Repo and Gem Bootstrap -Completed

### Implement
- Create gem skeleton (`lib`, `spec`, gemspec, version file).
- Add base configuration object and initializer template.
- Add install generator that writes initializer and folder structure.
- Set up CI baseline (bundle, test, lint).

### Test
- Verify gem loads in a dummy Rails app.
- Test install generator output (files created, idempotent behavior).
- Add smoke test for config defaults.
- Run `bundle exec rspec` and ensure baseline passes.

### Exit Criteria
- Gem installs and boots without runtime errors.
- Install generator works on a clean app and rerun.

---

## Phase 1 - Result and Error Contract - Completed

### Implement
- Add `Result.success` and `Result.failure` constructors.
- Add result query APIs (`success?`, `failure?`, `value`, `error`, `code`, `meta`).
- Add normalized error builders (`validation_error`, `not_found`, `conflict`, `unauthorized`, `unexpected`).
- Document minimal contract and examples.

### Test
- Unit tests for success/failure object behavior.
- Unit tests for each error builder shape.
- Contract tests for serialization of result payloads.
- Edge tests for missing metadata/details handling.

### Exit Criteria
- Result payloads are stable and predictable.
- Error schema is documented and covered by tests.

---

## Phase 2 - BaseService Core Lifecycle - Completed

### Implement
- Add `BaseService.call(action:, params:, context:)` entrypoint.
- Add shared context and parameter normalization helpers.
- Add extension points for subclass overrides.

### Test
- Unit tests for hook invocation order.
- Unit tests for subclass override behavior.
- Tests for invalid action handling and error return format.
- Tests for context pass-through and immutability assumptions.

### Exit Criteria
- Base execution path is reliable.
- Hook lifecycle is deterministic and tested.

---

## Phase 3 - CRUD Defaults (Create/Update/Destroy) - Completed

### Implement
- Add default `create`, `update`, and `destroy` implementations in `BaseService`.
- Add model resolution strategy and safe record lookup helper.
- Add standard mapping from ActiveRecord errors to result failures.
- Support custom override points per action.

### Test
- Integration tests with dummy model for create/update/destroy success.
- Validation-failure tests (returns failure result, not raised errors).
- Not-found and conflict-path tests.
- Transaction rollback tests for failure paths.

### Exit Criteria
- Core write actions are usable with minimal subclassing.
- CRUD failure behavior is consistent across actions.

---

## Phase 5 - Model Service Generator

### Implement
- Add generator to scaffold per-model service classes.
- Generate empty subclass with operation stubs (optional flags).
- Add namespace-aware generation for domain modules.
- Add overwrite protection and regeneration guidance messages.

### Test
- Generator tests for single model and namespaced model.
- Tests for idempotent rerun behavior.
- Tests for custom output paths and naming rules.
- Dummy app test proving generated class is callable.

### Exit Criteria
- Every model can be scaffolded into a service quickly.
- Generated output is deterministic and convention-compliant.

---

## Phase 6 - Bulk Operations

### Implement
- Add `bulk_create`, `bulk_update`, and `bulk_destroy`.
- Add per-item result aggregation with batch summary.
- Add transaction modes: `all_or_nothing` and `best_effort`.
- Add configurable limits and batch-level metadata.

### Test
- Integration tests for all bulk methods (happy paths).
- Mixed-result tests (partial success) with item-level errors.
- Transaction-mode tests for rollback vs best effort behavior.
- Boundary tests (empty input, oversized input, invalid records).

### Exit Criteria
- Bulk APIs are stable and return predictable batch contracts.
- Partial success behavior is explicit and tested.

---

## Phase 7 - Domain Router DSL (Core)

### Implement
- Add `DomainRouter.draw` DSL and operation mapping primitives.
- Add operation registry and route resolution logic.
- Add domain context propagation (`current_domain`, metadata).
- Add basic instrumentation hooks for router traces.

### Test
- DSL parser tests for valid/invalid definitions.
- Router resolution tests across multiple domains.
- Tests for context propagation into service execution.
- Tests for missing-route and duplicate-route errors.

### Exit Criteria
- Domain routes are declarative and deterministic.
- Operations resolve correctly with propagated context.

---

## Phase 8 - Cross-Domain Guardrails (Warn-Only)

### Implement
- Add detection for cross-domain operation calls.
- Add allowlist configuration for approved crossings.
- Emit warning events (non-blocking) with structured metadata.
- Add hooks for future strict-mode upgrade path.

### Test
- Tests for warning emission on unapproved cross-domain calls.
- Tests for allowlisted calls producing no warning.
- Formatter tests for warning payload structure.
- Regression test to confirm no runtime blocking in v1 mode.

### Exit Criteria
- Cross-domain leaks are visible without breaking runtime behavior.
- Warning format is CI and log friendly.

---

## Phase 9 - Architecture Checks and CI Reporter

### Implement
- Add checks for direct model access in controllers.
- Add checks for missing service class usage by model-facing actions.
- Build report formatter (`text` and `json`).
- Add CLI/task entrypoint for CI usage.

### Test
- Fixture-based tests for detector rules.
- Output snapshot tests for text/json reporter formats.
- CI task tests for exit behavior in warn-only mode.
- Scale sanity test on medium fixture set.

### Exit Criteria
- Teams can run checks locally and in CI with clear reports.
- Warn-only behavior remains default and non-blocking.

---

## Phase 10 - Docs and End-to-End Sample

### Implement
- Write quickstart (install, generate, first call).
- Write cookbook recipes (CRUD, bulk, domain routing, error mapping).
- Add legacy adoption guide (incremental migration strategy).
- Publish end-to-end sample flow in a dummy app.

### Test
- Validate all doc commands in a clean environment.
- Execute sample flow and verify outputs match docs.
- Add doc-link and snippet integrity checks.
- Run new-user acceptance pass (time-to-first-feature target).

### Exit Criteria
- A new user can complete one domain feature in under 30 minutes.
- Documentation is executable and aligned with current gem behavior.

---

## Phase 11 - v1 Stabilization and Release

### Implement
- Freeze public DSL and result contract.
- Remove/rename unstable APIs before GA.
- Finalize changelog and migration notes.
- Tag and release `v1.0.0`.

### Test
- Full regression suite run.
- Compatibility test matrix for supported Rails/Ruby versions.
- Release candidate validation in at least one internal app.
- Verify generated artifacts and release packaging.

### Exit Criteria
- Public APIs are stable and documented.
- `v1.0.0` is releasable with green test and lint pipelines.

---

## Optional Post-v1 Phases

### Phase 12 - DX Expansion (v1.1.x)
- Implement advanced generators and response helpers.
- Add performance optimizations for checks/router.
- Test generator UX and benchmark critical paths.

### Phase 13 - Strict Mode Preview (v1.2.x)
- Add opt-in strict mode flags and per-domain toggles.
- Add CI fail-on-violation option.
- Test migration path from warn-only to strict mode.
