# ADR-0003: Pipeline Context Propagation

**Status:** Accepted  
**Date:** 2026-04-20  
**RFC:** [1.3.0 Pipelines & Hooks](../rfcs/1.3.0-pipelines-and-hooks.md)

---

## Context

`Railsmith::Context` is an immutable value object (frozen after construction) that carries cross-cutting state: `request_id`, `current_domain`, `actor_id`, `actor` (in-process only; not serialized by `to_h`), and arbitrary extras. In v1.2, context is thread-local (`Context.current`) and is set by `ContextPropagation#call` before dispatching to a service action.

A pipeline calls multiple services in sequence. The pipeline runner must decide:

1. Which context object is passed to each step service.
2. Whether steps can contribute new context keys (and if so, how).
3. How context relates to the accumulated params (the "pipeline context" mentioned in the plan).

The word "context" is overloaded in this RFC. To disambiguate:
- **Railsmith context** — the `Railsmith::Context` object (domain, actor, request_id).
- **Pipeline context** — the accumulated merged params hash that grows as steps complete.

---

## Decision

### Rule 1: The Railsmith context is shared and immutable across all steps

The `Railsmith::Context` object that was active when `Pipeline.call` was invoked is passed unchanged to every step service. No step can modify it.

```ruby
result = CheckoutPipeline.call(
  action:  :run,
  params:  { cart_id: 42 },
  context: { actor_id: current_user.id, actor: current_user, current_domain: :commerce }
)
# Every step (CartService, InventoryService, PaymentService) receives
# the same Context object with actor_id and current_domain set.
```

Rationale: `Context` is designed as an immutable audit record. Allowing steps to mutate or replace it would break the audit invariant and make it impossible to reason about which domain or actor performed an operation.

### Rule 2: Steps cannot inject new keys into the Railsmith context

If a step needs to produce metadata for downstream steps, it should do so via `result.value` (which flows into the pipeline context / accumulated params), not by producing a new `Context`. The `Context` is a property of the call site, not of individual steps.

### Rule 3: The pipeline context (accumulated params) is separate from the Railsmith context

The pipeline's accumulated params (`original_params.merge(accumulated_value)`) are passed as the `params:` argument to each step service. The `context:` argument is always the shared, frozen `Railsmith::Context`.

```ruby
# Runner pseudocode
def run_step(step_def, accumulated_params, context)
  params = resolve_inputs(step_def, accumulated_params)
  step_def.service.call(action: step_def.action, params:, context:)
end
```

### Rule 4: Thread-local context wrapping is set once at pipeline entry

`ContextPropagation` uses `Context.with { }` to wrap execution in a thread-local context scope. The pipeline runner calls `Context.with(pipeline_context) { ... }` once at entry, covering the entire pipeline run. Individual step services find `Context.current` already set and do not need to re-wrap.

This means step services behave identically whether invoked directly or as part of a pipeline—they read `Context.current` the same way in both cases.

### Rule 5: Pipeline metadata is attached to the Result, not to the Context

Information about the pipeline run (step count, duration, step name at failure) is surfaced via `result.meta[:pipeline]`, not embedded in the context. This keeps the context clean for its primary purpose (audit, domain, actor) and avoids the context becoming a grab-bag.

```ruby
result.meta[:pipeline]
# => {
#   name:       "CheckoutPipeline",
#   steps_run:  3,
#   failed_at:  :charge_payment,   # nil on success
#   duration_ms: 145.2
# }
```

---

## Consequences

### Simplicity

Every step service receives the same context it would receive if called standalone. No special pipeline-aware service interface is required. Existing v1.2 services work as pipeline steps without modification.

### Traceability

All events emitted by step services share the same `request_id` (from the shared context). Distributed tracing systems can group all pipeline step events under a single trace without additional correlation logic.

### Domain enforcement

Because `current_domain` does not change between steps, cross-domain calls within a pipeline are subject to the same `CrossDomainGuard` checks as standalone calls. A pipeline declared in the `:commerce` domain cannot silently call a `:billing`-domain service without triggering the guard. This is intentional—pipelines do not bypass domain boundaries.

### No dynamic context enrichment

Steps cannot add keys to the context for downstream steps to read. If step B needs data produced by step A, that data must flow through `result.value` → accumulated params → step B's `params`. This is a deliberate constraint: using the context as a side channel for inter-step communication would make execution order an implicit coupling.

### Context in around hooks

Around hooks declared on a pipeline step's service class read `Context.current`, which is the pipeline's shared context. This is consistent with how around hooks behave when services are called standalone.

---

## Alternatives Considered

**Each step gets a fresh context derived from the previous step's result:** Rejected. This would allow steps to progressively enrich the context, but breaks the audit invariant (who is the actor for this pipeline run?) and requires step services to know they're in a pipeline.

**Pipeline constructs a new context with a `pipeline_id` key injected:** Accepted as a future enhancement, not in v1.3.0 scope. A `pipeline_id` in the context would help distributed tracing but is not needed for correct behavior. It can be added in a minor release without breaking changes.

**Steps share a mutable "pipeline bag" separate from both context and params:** Rejected. Two separate shared mutable structures (params + bag) create confusion about where to put step outputs. The accumulated params hash is sufficient; the context remains for call-site metadata only.
