# ADR-0002: Hook Inheritance Rules

**Status:** Accepted  
**Date:** 2026-04-20  
**RFC:** [1.3.0 Pipelines & Hooks](../rfcs/1.3.0-pipelines-and-hooks.md)

---

## Context

Railsmith services form class hierarchies (e.g., `SubscriptionService < OrderService < BaseService`). When hooks are declared on a parent class, subclasses need a predictable answer to two questions:

1. Do subclasses automatically inherit parent hooks?
2. In what order do parent and child hooks run relative to each other?
3. Can a subclass suppress an inherited hook?

Ruby's module system provides `inherited` callbacks and `prepend` / `include` stacking, but none of these directly solve hook ordering because hooks are stored in a class-level registry, not in the method chain.

---

## Decision

### Rule 1: Subclasses inherit all parent hooks

When a class is subclassed, its `HookRegistry` is deep-duplicated into the subclass via `inherited`. The subclass starts with a copy of the parent's `HookChain` and can append to it. Changes to the parent's registry after the subclass is defined do **not** propagate downward.

```ruby
class Base < Railsmith::BaseService
  before :create do
    log("base before create")
  end
end

class Child < Base
  before :create do
    log("child before create")
  end
end

# Execution for Child#create:
# 1. "base before create"   (inherited, runs first)
# 2. "child before create"  (child-declared, runs after)
```

### Rule 2: Parent hooks run before child hooks (declaration order within each tier)

Within the same tier (global → parent → child), hooks run in the order they were declared. Across tiers, the hierarchy goes outermost-first:

```
global hooks (declaration order)
  → parent class hooks (declaration order)
    → child class hooks (declaration order)
      → [action]
    → child after hooks (declaration order)
  → parent after hooks (declaration order)
global after hooks (declaration order)
```

Around hooks follow the same nesting: the outermost (global/parent) around hook wraps the innermost (child/action).

### Rule 3: Named hooks can be skipped by subclasses

An inherited hook can be suppressed by naming it at declaration and calling `skip_before` / `skip_after` / `skip_around` / `skip_hook` in the subclass.

```ruby
class Base < Railsmith::BaseService
  before :create, name: :rate_limit do
    RateLimiter.check!(context[:actor_id])
  end
end

class InternalService < Base
  # Internal services are not rate-limited
  skip_before :create, :rate_limit
end
```

`skip_hook :rate_limit` removes the named entry from the subclass's copy of the `HookChain`. It does not affect the parent class.

Skipping an unnamed hook (i.e., one without `name:`) is not supported. This is intentional: unnamed hooks cannot be unambiguously identified, and forcing a name makes skip intent explicit.

### Rule 4: `skip_*` does not propagate further down the hierarchy

If `Child` skips `:rate_limit`, `GrandChild < Child` does not inherit the skip—it inherits `Child`'s chain, which already has `:rate_limit` removed. The net effect is that the skip is preserved, but only because the entry was removed from `Child`'s registry before `GrandChild` inherits.

---

## Consequences

### Predictability

Developers can inspect a class's effective hook chain at any time:

```ruby
OrderService.hooks_for(:create)
# => [
#   #<HookEntry type=:before actions=[:create] name=:audit_log ...>,
#   #<HookEntry type=:before actions=[:create] name=nil ...>,
#   ...
# ]
```

This introspection helper surfaces the merged, ordered list including inherited entries.

### Deep-dup on inheritance, not on call

The registry dup happens once in `inherited`, not on every `call`. This keeps per-call overhead at zero for hook resolution: the chain is computed at class load time, not at dispatch time.

### No dynamic hook declaration after class load

Declaring a hook inside a method (e.g., in an initializer or `configure` block that runs late) after subclasses are already defined will not propagate to those subclasses. This is a known limitation accepted for v1.3.0. Dynamic hooks introduce race conditions in multi-threaded Rails apps and are out of scope.

### Around hook nesting

Around hooks from parent classes wrap around those of child classes. A parent around hook that forgets to `yield` will silently swallow child hooks and the action. The runner raises `Railsmith::Hooks::AroundHookNotYieldedError` if the action block is never called, to surface this class of bug in development and test.

---

## Alternatives Considered

**Child hooks run before parent hooks (innermost-first):** Rejected. The parent declares invariants (authorization, rate limiting) that must run before child-declared customizations. A parent hook that checks authorization and bails early should run before a child hook that does expensive work.

**No inheritance; subclasses must re-declare all hooks:** Rejected. This eliminates the core value of hooks in a hierarchy—a cross-cutting concern declared once on a base class would need to be copied to every leaf service.

**Shared registry (no dup on inheritance):** Rejected. A shared registry means adding a hook to a subclass modifies the parent's chain—a footgun. Deep-dup is the same strategy used by `InputRegistry` and `AssociationRegistry` in v1.2.
