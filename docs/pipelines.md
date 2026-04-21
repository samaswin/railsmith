# Service Pipelines

Railsmith pipelines compose multiple services into a single sequential workflow with automatic param forwarding, fail-fast semantics, rollback support, and instrumentation. They are the service-layer equivalent of the Interactor organizer or dry-transaction step pattern.

Pipelines are **purely additive** — existing services and `call` sites are unaffected.

---

## Quick start

```ruby
class CheckoutPipeline < Railsmith::Pipeline
  domain :commerce

  step :validate_cart,     service: CartService,         action: :validate
  step :reserve_inventory, service: InventoryService,    action: :reserve,
                           rollback: :unreserve
  step :charge_payment,    service: PaymentService,      action: :charge,
                           inputs: { amount: :cart_total }, rollback: :refund
  step :create_order,      service: OrderService,        action: :create
  step :send_confirmation, service: NotificationService, action: :send_receipt
end

result = CheckoutPipeline.call(params: { cart_id: 42, user_id: 7 }, context: ctx)

if result.success?
  puts result.value  # => value from the last step
else
  puts result.code                    # => "validation_error", "not_found", …
  puts result.meta[:pipeline_name]    # => "CheckoutPipeline"
  puts result.meta[:pipeline_step]    # => :charge_payment
end
```

Generate the boilerplate with:

```bash
rails generate railsmith:pipeline Checkout
```

---

## The `step` DSL

```ruby
step name,
     service:,
     action:,
     inputs:             nil,
     rollback:           nil,
     if:                 nil,   # or unless:
     on_failure_continue: false
```

| Option | Type | Description |
|--------|------|-------------|
| `name` | Symbol | Identifier used in events and error metadata |
| `service:` | Class | A `Railsmith::BaseService` subclass |
| `action:` | Symbol | Forwarded as `action:` to `service.call` |
| `inputs:` | Hash | `{ target_key => source_key }` renames applied before forwarding |
| `rollback:` | Symbol / Proc | Compensation handler; invoked when a later step fails |
| `if:` / `unless:` | Symbol / Proc | Guard condition; step is skipped when the condition is not met |
| `on_failure_continue:` | Boolean | When `true`, a failure does not halt the pipeline |

---

## Worked example — CheckoutPipeline

This section walks through a complete checkout flow, explaining each option as it appears.

### 1. Define the services

```ruby
class CartService < Railsmith::BaseService
  model Cart
  domain :commerce

  def validate
    cart = Cart.find(params[:cart_id])
    return Result.failure(error: Errors.validation_error(message: "Cart is empty")) if cart.items.none?

    Result.success(value: { cart_total: cart.total_cents, cart: cart })
  end
end

class InventoryService < Railsmith::BaseService
  domain :commerce

  def reserve
    # reserve stock, return reservation token
    token = StockLedger.reserve(params[:cart_id])
    Result.success(value: { reservation_token: token })
  end

  def unreserve
    StockLedger.release(params[:reservation_token])
    Result.success
  end
end

class PaymentService < Railsmith::BaseService
  domain :commerce

  def charge
    charge = PaymentGateway.charge(
      amount:  params[:amount],
      user_id: params[:user_id]
    )
    Result.success(value: { charge_id: charge.id })
  end

  def refund
    PaymentGateway.refund(params[:charge_id])
    Result.success
  end
end

class OrderService < Railsmith::BaseService
  model Order
  domain :commerce

  def create
    order = Order.create!(
      cart_id:  params[:cart_id],
      charge_id: params[:charge_id],
      user_id:  params[:user_id]
    )
    Result.success(value: { order_id: order.id })
  end
end

class NotificationService < Railsmith::BaseService
  domain :commerce

  def send_receipt
    Mailer.receipt(order_id: params[:order_id]).deliver_later
    Result.success(value: { notified: true })
  end
end
```

### 2. Define the pipeline

```ruby
class CheckoutPipeline < Railsmith::Pipeline
  domain :commerce

  step :validate_cart,     service: CartService,         action: :validate
  step :reserve_inventory, service: InventoryService,    action: :reserve,
                           rollback: :unreserve
  step :charge_payment,    service: PaymentService,      action: :charge,
                           inputs: { amount: :cart_total }, rollback: :refund
  step :create_order,      service: OrderService,        action: :create
  step :send_confirmation, service: NotificationService, action: :send_receipt
end
```

### 3. Call it

```ruby
ctx    = Railsmith::Context.new(domain: :commerce, actor_id: current_user.id)
result = CheckoutPipeline.call(params: { cart_id: 42, user_id: current_user.id }, context: ctx)

if result.success?
  redirect_to order_path(result.value[:order_id])
else
  render json: result.to_h, status: :unprocessable_entity
end
```

---

## Param forwarding

Each step receives **accumulated params** — the original params hash grown by merging each step's `result.value` (when it is a `Hash`) before passing to the next step. Non-Hash return values (ActiveRecord objects, etc.) do not pollute the accumulated params.

```
Initial params:   { cart_id: 42, user_id: 7 }

After :validate_cart   →  merged { cart_total: 14999, cart: #<Cart> }
After :reserve_inventory → merged { reservation_token: "tok_abc" }
After :charge_payment  →  merged { charge_id: "ch_xyz" }
After :create_order    →  merged { order_id: 99 }
```

### Renaming keys with `inputs:`

Use `inputs:` when a step expects a different key name than what accumulated params carry:

```ruby
# PaymentService#charge expects :amount, but accumulated params has :cart_total
step :charge_payment, service: PaymentService, action: :charge,
     inputs: { amount: :cart_total }
```

The rename is applied only to the params forwarded to that step — `accumulated_params` retains the original `:cart_total` key. When a source key listed in `inputs:` is absent, `Railsmith::Pipeline::ParamMappingError` is raised with the step name and missing key.

---

## Fail-fast behavior

The pipeline halts on the **first failing step** and returns that step's failure Result, annotated with pipeline metadata:

```ruby
result.failure?                     # => true
result.code                         # => the failing step's error code
result.meta[:pipeline_name]         # => "CheckoutPipeline"
result.meta[:pipeline_step]         # => :charge_payment
```

Steps after the failing step are never executed. Steps before it are rolled back (if they declared a `rollback:`).

---

## Rollback and compensation

Declare a `rollback:` handler on any step that has side-effects. When a later step fails, the runner walks already-completed steps **in reverse order** and invokes each rollback.

```ruby
step :reserve_inventory, service: InventoryService, action: :reserve,
     rollback: :unreserve
step :charge_payment,    service: PaymentService,   action: :charge,
     rollback: :refund
```

If `:create_order` fails after both `:reserve_inventory` and `:charge_payment` have succeeded, the runner calls:

1. `PaymentService.call(action: :refund, params: …)`
2. `InventoryService.call(action: :unreserve, params: …)`

The rollback receives the params that were forwarded to the forward step, merged with that step's `result.value` (when it is a Hash).

### Proc rollbacks

Pass a lambda when the compensation logic does not map cleanly to a service action:

```ruby
step :send_webhook, service: WebhookService, action: :notify,
     rollback: ->(step_result, context) {
       WebhookLog.mark_cancelled(step_result.value[:webhook_id])
       Railsmith::Result.success
     }
```

### Rollback failures

Railsmith never aborts a compensation sequence because one rollback failed — every step gets a chance to roll back. If any rollback itself returns a failure, the failures are collected in `result.meta[:rollback_failures]`:

```ruby
result.meta[:rollback_failures]
# => [{ step: :charge_payment, error: #<ErrorPayload code="unexpected" …> }]
```

### Idempotency

Design rollback handlers to be **idempotent** — they may be invoked more than once if the pipeline is retried after a partial failure. A double-refund is far worse than a no-op refund.

---

## Conditional steps

Skip steps based on runtime state using `if:` or `unless:`. Only one can be present on a step.

### Inline proc

```ruby
step :apply_coupon, service: CouponService, action: :apply,
     if: ->(params, _ctx) { params[:coupon_code].present? }

step :charge_vat, service: TaxService, action: :apply_vat,
     unless: ->(params, ctx) { ctx[:tax_exempt] }
```

The proc receives `(accumulated_params, context)` and must return a truthy/falsy value. Skipped steps emit a `pipeline.step.skipped.railsmith` instrumentation event and are **not** rolled back on failure.

### Named guards

Extract complex predicates into reusable named guards declared at the pipeline level:

```ruby
class CheckoutPipeline < Railsmith::Pipeline
  guard :has_coupon? do |params, _ctx|
    params.key?(:coupon_code) && params[:coupon_code].present?
  end

  guard :tax_exempt? do |_params, ctx|
    ctx[:tax_exempt] == true
  end

  step :validate_cart,  service: CartService,   action: :validate
  step :apply_coupon,   service: CouponService, action: :apply,
                        if: :has_coupon?
  step :charge_vat,     service: TaxService,    action: :apply_vat,
                        unless: :tax_exempt?
  step :charge_payment, service: PaymentService, action: :charge,
                        rollback: :refund
end
```

Guards are looked up by symbol name at runtime. Referencing an undefined guard raises `Railsmith::Pipeline::GuardNotFoundError`.

---

## Non-critical steps (`on_failure_continue:`)

Mark a step with `on_failure_continue: true` to allow the pipeline to proceed even if that step fails. The step is not rolled back, and subsequent steps run as normal.

```ruby
step :send_confirmation, service: NotificationService, action: :send_receipt,
     on_failure_continue: true
```

Use this for steps where failure is acceptable (analytics events, non-critical notifications) but should not abort the primary workflow.

---

## `call!` — raising variant

Like `BaseService.call!`, `Pipeline.call!` raises `Railsmith::Failure` on the first step failure:

```ruby
result = CheckoutPipeline.call!(params: { cart_id: 42 }, context: ctx)
# raises Railsmith::Failure if any step fails

rescue Railsmith::Failure => e
  e.result.meta[:pipeline_step]  # => :charge_payment
  e.code                         # => "unexpected"
end
```

---

## Instrumentation

Three ActiveSupport instrumentation events are emitted per pipeline run:

| Event | When fired | Payload keys |
|-------|-----------|--------------|
| `pipeline.step.railsmith` | After each step completes (success or failure) | `:pipeline`, `:step`, `:status`, `:duration` |
| `pipeline.step.skipped.railsmith` | When a conditional step is skipped | `:pipeline`, `:step` |
| `pipeline.rollback.railsmith` | After each rollback handler runs | `:pipeline`, `:step`, `:status`, `:duration` |
| `pipeline.railsmith` | Once, after the entire run | `:pipeline`, `:status`, `:duration` |

Subscribe with ActiveSupport::Notifications as usual:

```ruby
ActiveSupport::Notifications.subscribe("pipeline.step.railsmith") do |_name, _start, _finish, _id, payload|
  Rails.logger.info("[pipeline] #{payload[:pipeline]}##{payload[:step]} — #{payload[:status]} (#{(payload[:duration] * 1000).round}ms)")
end
```

---

## Pipeline inheritance

Subclasses inherit the parent's step list and guard registry (deep-copied at class definition time):

```ruby
class ExtendedCheckoutPipeline < CheckoutPipeline
  step :send_sms, service: SmsService, action: :send_sms
end
```

Adding steps to the parent after the subclass is defined does **not** propagate to the subclass.

---

## Combining pipelines with result chaining

For lighter-weight composition without a full pipeline class, use `Result#and_then`:

```ruby
result = CartService.call(action: :validate, params: { cart_id: 42 }, context: ctx)
  .and_then { |cart_data| PaymentService.call(action: :charge, params: cart_data, context: ctx) }
  .and_then { |charge_data| OrderService.call(action: :create, params: charge_data, context: ctx) }

result.success?  # chain short-circuits on first failure
```

See [Result Chaining](./result-chaining.md) or [Cookbook](./cookbook.md) for fluent patterns. Use `Pipeline` when you need rollback support, instrumentation, or more than 3–4 steps.

---

## Generator

```bash
rails generate railsmith:pipeline Checkout
# app/pipelines/checkout_pipeline.rb
# spec/pipelines/checkout_pipeline_spec.rb
```

The generated class includes commented-out examples for `step`, `rollback:`, and `if:`.

List all registered pipelines and their steps:

```bash
rake railsmith:pipelines
```

---

## Best practices

- **Keep steps thin** — each step should delegate to a service with a single responsibility. Business logic lives in services, not in the pipeline.
- **Return Hash values from steps** — only Hash return values are merged into accumulated params. Return an object only when you don't want it forwarded.
- **Name rollback handlers explicitly** — `refund`, `unreserve`, `cancel_webhook` are clearer than generic names.
- **Design rollbacks to be idempotent** — pipelines may be retried after partial failures.
- **Prefer `guard` for complex conditions** — inline lambdas with more than one condition are hard to test; extract them into named guards.
- **Use `on_failure_continue:` sparingly** — it hides failures from callers. Always log or instrument skipped failures.

---

## Further reading

- [RFC: Pipelines & Hooks](./rfcs/1.3.0-pipelines-and-hooks.md)
- [ADR-0001: Rollback Ordering](./adrs/0001-rollback-ordering.md)
- [ADR-0003: Pipeline Context Propagation](./adrs/0003-pipeline-context-propagation.md)
- [Hooks guide](./hooks.md) — lifecycle hooks on individual services
- [Cookbook](./cookbook.md) — more service-layer patterns
