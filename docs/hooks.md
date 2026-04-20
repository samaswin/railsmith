# Lifecycle Hooks

Railsmith's hook system lets you attach `before`, `after`, and `around` callbacks to any service action. Hooks are ideal for cross-cutting concerns that would otherwise get copy-pasted across services: audit logging, event publishing, metrics, authorization, rate limiting, and request scoping.

Hooks are **purely additive** — services that declare no hooks behave exactly as they did before v1.3.

---

## Quick start

```ruby
class OrderService < Railsmith::BaseService
  model Order

  before :create do
    AuditLog.record(
      service: self.class.name,
      actor: context[:actor_id]
    )
  end

  after :create do |result|
    EventBus.publish("order.created", result.value) if result.success?
  end

  around :create do |action|
    Metrics.time("order.create") { action.call }
  end
end
```

Every hook body is evaluated in the service instance context, so `params`, `context`, and any service helper methods are directly accessible — no wrappers, no `service.foo` prefixing.

---

## The three hook types

### `before`

Runs **before** the action method. Takes the service's current `params` as an optional block argument.

```ruby
before :create do |params|
  params[:created_at] = Time.current
end

before :create, :update do
  ensure_tenant_isolation!
end
```

A `before` hook that raises aborts the action entirely — the exception propagates up through `BaseService#call`.

### `after`

Runs **after** the action, with the action's `Result` passed as the block argument. Fires regardless of whether the result is a success or a failure.

```ruby
after :create do |result|
  if result.success?
    EventBus.publish("order.created", result.value)
  else
    ErrorTracker.capture(result.error)
  end
end
```

After hooks are **observational** — they cannot change the Result that the caller sees. If you need to transform the outcome, use `around` instead.

### `around`

Wraps the action entirely. The block receives a callable action; it **must** invoke it exactly once, or Railsmith raises `Railsmith::Hooks::AroundHookNotYieldedError` to catch the mistake early.

```ruby
around :charge do |action|
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = action.call
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  Metrics.record("charge.duration_ms", elapsed * 1000)
  result
end
```

Because an around hook's return value becomes the Result for the call, you can use it to short-circuit, retry, or transform:

```ruby
around :send_email do |action|
  if Rails.env.test?
    Railsmith::Result.success(value: { suppressed: true })
  else
    action.call
  end
end
```

When multiple `around` hooks are declared on the same action, they nest in declaration order — the first declared is the **outermost** wrapper.

---

## Execution order

Given a service with a full sandwich of hooks, actions run in this order (outermost wraps innermost):

```
global before hooks                (declaration order)
  parent class before hooks        (declaration order)
    child class before hooks       (declaration order)
      around hooks outermost -> innermost
        [the action method runs]
      around hooks unwind
    child class after hooks        (declaration order)
  parent class after hooks         (declaration order)
global after hooks                 (declaration order)
```

This mirrors the ordering developers expect from Rails' own `ActionController` callbacks: parent concerns run before child ones in the `before` phase, and in reverse for the `after` phase.

---

## Conditional hooks

Every hook accepts an `if:` or `unless:` option. Conditions can be symbols (instance method names) or callables (procs / lambdas):

```ruby
# Symbol predicate — calls `admin?` on the service instance.
before :destroy, if: :admin? do
  notify_stakeholders
end

# Lambda — receives the service instance.
before :update, unless: ->(svc) { svc.params[:draft] } do
  validate_publish_state
end

# Non-lambda Proc — instance_exec'd in the service context.
before :create, if: proc { context[:live_mode] } do
  ensure_live_credentials
end
```

Declaring both `if:` and `unless:` on the same hook raises an `ArgumentError` at class-load time.

---

## Hook inheritance

Subclasses automatically inherit all of their parent's hooks. Parent hooks run first; child hooks extend the chain:

```ruby
class Base < Railsmith::BaseService
  before :create do
    log("base before create")   # runs first
  end
end

class Child < Base
  before :create do
    log("child before create")  # runs after the parent's hook
  end
end
```

The parent's hook chain is deep-duplicated into the subclass when it is defined (see [ADR-0002](./adrs/0002-hook-inheritance-rules.md) for the full rules). This means adding a hook to the parent *after* the subclass is defined does not propagate to the subclass — declare hooks at class load time, not at runtime.

### Skipping inherited hooks

Inherited hooks can be suppressed by naming them at declaration and calling `skip_before`, `skip_after`, `skip_around`, or the type-agnostic `skip_hook` in the subclass:

```ruby
class Base < Railsmith::BaseService
  before :create, name: :rate_limit do
    RateLimiter.check!(context[:actor_id])
  end
end

class InternalService < Base
  # Internal services bypass the rate limiter.
  skip_before :create, :rate_limit

  # Equivalent, type-agnostic:
  # skip_hook :rate_limit
end
```

Only **named** hooks can be skipped. Unnamed hooks cannot be unambiguously identified, so Railsmith requires a name before allowing suppression.

---

## Global hooks

Cross-cutting concerns that apply to every service (or to every service in a specific domain) belong in `Railsmith.configure`:

```ruby
Railsmith.configure do |config|
  # Every service action — runs before any class-level hooks.
  config.before_action :create do
    RateLimiter.check!(context[:actor_id])
  end

  # Multiple actions in one call.
  config.after_action :create, :update do |result|
    MetricsCollector.record(result)
  end

  # Only services declared with `domain :commerce`.
  config.around_action :charge, only: [:commerce] do |action|
    CommerceSandbox.wrap { action.call }
  end
end
```

Global hooks accept the same `if:`, `unless:`, and `name:` options as class-level hooks. The `only:` filter matches against the **service** domain (the class-level `domain :x` declaration), not the caller's context domain.

Global hooks are stored on `Railsmith.configuration.global_hooks` and can be reset via `Railsmith.configuration.reset_global_hooks!` — useful between test examples.

---

## Introspection

To see the effective hook chain for an action on any class (including inherited entries):

```ruby
OrderService.hooks_for(:create)
# => #<Railsmith::Hooks::HookChain entries=[
#      #<HookEntry type=:before actions=[:create] name=:audit_log ...>,
#      #<HookEntry type=:around actions=[:create] name=nil ...>,
#      ...
#    ]>

OrderService.hooks_for(:create).of_type(:before).size  # => 2
```

This helper is especially handy when a hook ordering bug appears far from the declaration site — you can print the resolved chain without running the service.

---

## Common patterns

### Audit logging for mutating actions

```ruby
class ApplicationService < Railsmith::BaseService
  before :create, :update, :destroy, name: :audit_log do
    AuditLog.record(
      service: self.class.name,
      action:  __method__,  # name of the containing action is not available inside a block;
                            # use the approach below if you need the action name explicitly
      actor:   context[:actor_id],
      tenant:  context[:tenant_id]
    )
  end
end
```

Because hooks do not know which action they're running against, services that need the action name can capture it inside the action method itself (or around the full call via an around hook).

### Event publishing on success

```ruby
after :create do |result|
  EventBus.publish("#{self.class.event_prefix}.created", result.value) if result.success?
end
```

### Timing + instrumentation

```ruby
around :charge do |action|
  Railsmith::Instrumentation.instrument(
    "service.charge",
    service: self.class.name,
    domain:  current_domain
  ) { action.call }
end
```

### Authorization guard

```ruby
before :destroy, if: :unauthorized? do
  return Railsmith::Result.failure(
    code: :unauthorized,
    message: "Only admins can destroy orders"
  )
end

def unauthorized?
  context[:actor_role] != :admin
end
```

(Note: `before` hooks cannot short-circuit the action — their return value is ignored. Use an `around` hook to return a failure Result without invoking the action.)

### Short-circuiting with an around hook

```ruby
around :destroy do |action|
  if context[:actor_role] != :admin
    Railsmith::Result.failure(code: :unauthorized, message: "admin only")
  else
    action.call
  end
end
```

---

## Interaction with other Railsmith features

- **Inputs DSL** — input resolution runs *before* any hooks. If required inputs are missing, the call returns a validation failure without invoking the hook chain.
- **`call!`** — when an action wrapped by hooks returns a failure Result, `call!` still raises `Railsmith::Failure` as usual. After hooks still fire before the exception is raised.
- **Instrumentation** — hooks run inside the existing `service.call.railsmith` instrumentation event, so timing captured by `ActiveSupport::Notifications` covers the hook sandwich.
- **CRUD transactions** — `CrudTransactions` wraps database writes in a transaction inside the action. Around hooks therefore run outside the transaction by default; if you need to run code inside the same transaction, do so from within the action method itself or by overriding the CRUD entry point.

---

## Further reading

- [RFC: Pipelines & Hooks](./rfcs/1.3.0-pipelines-and-hooks.md)
- [ADR-0002: Hook Inheritance Rules](./adrs/0002-hook-inheritance-rules.md)
- [Cookbook](./cookbook.md) for more service-layer patterns
