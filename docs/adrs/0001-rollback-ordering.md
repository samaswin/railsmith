# ADR-0001: Rollback Ordering

**Status:** Accepted  
**Date:** 2026-04-20  
**RFC:** [1.3.0 Pipelines & Hooks](../rfcs/1.3.0-pipelines-and-hooks.md)

---

## Context

When a pipeline step fails, previously completed steps may have produced side effects (database writes, charges, emails, third-party API calls) that must be compensated. The pipeline needs a deterministic ordering strategy for invoking rollback handlers so that developers can reason about and test compensation logic.

Two orderings are feasible:

1. **LIFO (reverse execution order)** — roll back the most recently completed step first, working backwards.
2. **FIFO (execution order)** — roll back in the same order steps ran.

A third option—parallel rollback—is rejected as out of scope for v1.3.0 (no parallel step execution exists yet, and parallel rollback introduces complexity around partial rollback failures).

---

## Decision

**Use LIFO (last-in, first-out) ordering for rollback.**

When a pipeline step fails, the runner walks the list of successfully completed steps in reverse execution order and invokes each step's `rollback:` handler.

```
Execution order:   step_a → step_b → step_c → [step_d fails]
Rollback order:              step_c → step_b → step_a
```

Only steps that completed with a `:success` status are rolled back. The failing step itself is not rolled back (it did not complete successfully). Skipped steps are never rolled back.

---

## Consequences

### Why LIFO

**Dependency inversion:** Steps further along the pipeline tend to depend on the outputs of earlier steps. Undoing the most recent work first is the natural unwinding order—analogous to stack unwinding in exception handling and transactional savepoint release.

**Predictability:** Given execution order A → B → C → D(fail), rolling back C before B matches developer intuition. Rolling back A before C would leave dangling references (e.g., releasing stock before cancelling the charge that paid for it).

**Consistency with existing patterns:** `CrudTransactions` already uses ActiveRecord transaction rollback, which is LIFO in savepoint semantics. Pipeline rollback follows the same mental model.

### Rollback failure handling

Rollback handlers can themselves fail. The pipeline runner:

1. Continues rolling back remaining steps regardless of rollback failures (best-effort).
2. Collects all rollback failures into `result.meta[:pipeline][:rollback_errors]`.
3. Surfaces the **primary failure** as the pipeline `Result`; rollback errors are metadata, not the top-level error.

This prevents a failing rollback from silently suppressing the original error.

```ruby
result.meta[:pipeline][:rollback_errors]
# => [{ step: :reserve_stock, error: <ErrorPayload> }]
```

### Idempotency requirement

Rollback handlers **must be idempotent**. The pipeline makes no guarantee that a handler will be called exactly once (network errors, process restarts, re-enqueued jobs). This is documented as a hard requirement in the hooks guide and enforced only by convention.

### Skipped steps

Steps skipped via `if:` / `unless:` guards are **never rolled back**, because they never ran. Their `StepExecution#status` is `:skipped` and the runner checks this before attempting rollback.

### Steps without `rollback:`

Steps that declare no `rollback:` handler are silently skipped during the rollback pass. This is intentional: not all side effects require compensation (e.g., a read-only validation step).

### Instrumentation

Each rollback invocation emits a `pipeline.rollback.railsmith` event with:

```ruby
{
  pipeline: "CheckoutPipeline",
  step:     :reserve_stock,
  status:   :success | :failure,   # rollback's own outcome
  duration_ms: 12.4
}
```

---

## Alternatives Considered

**FIFO rollback:** Rejected. Rolling back A before C would undo foundation work while dependent work (C) is still partially committed—leaving the system in a harder-to-reason-about state.

**Parallel rollback:** Rejected for v1.3.0. Adds significant complexity (concurrency, partial failure aggregation) without clear benefit at this scale. Revisit if async pipeline steps are added.

**Explicit rollback order DSL:** Rejected. Adding a `rollback_order:` class macro would make the common case verbose. LIFO is correct for 95%+ of pipelines; the 5% can be handled with a custom `rollback` method that calls sub-handlers in the desired order.
