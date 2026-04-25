# Railsmith

Railsmith helps you manage complex multi-step workflows in Rails apps — the kind where business logic spans multiple models, touches external services, and needs clear success/failure handling at every step.

It is not a replacement for Rails models or controllers. It's for the cases where those alone aren't enough.

**Requirements**: Ruby >= 3.1.0, Rails 7.0–8.x

---

## Structured results, always

Every service call returns a `Railsmith::Result`. Success or failure, the shape is always the same — no exceptions to rescue, no inconsistent return values.

```ruby
result = OrderService.call(action: :create, params: order_params, context: ctx)

if result.success?
  render json: result.value, status: :created
else
  render json: result.error.to_h, status: :unprocessable_entity
end
```

```ruby
result.success?       # => true / false
result.value          # => the returned object or data
result.error.code     # => "validation_error" | "not_found" | "conflict" | "unauthorized" | "unexpected"
result.error.message  # => human-readable message
result.error.details  # => structured detail hash (e.g. field-level validation errors)
```

This is the part of Railsmith that applies everywhere, even if you adopt nothing else.

---

## Is this for you?

If your Rails app is small and moving fast, you probably don't need this. Reach for models first. Active Record callbacks, validations, and scopes handle a lot, and adding abstraction too early is a real cost.

Railsmith is extracted from a production app that crossed the threshold where that stopped being enough. The inflection point looked like this:

- Multi-step workflows — validate cart → reserve inventory → charge payment → create order — each step needing independent rollback on failure
- `accepts_nested_attributes_for` silently skipping service-level validations on associated records
- No consistent answer to "what does this action return when it fails?"
- Cross-domain calls (billing code touching identity models) with no warning and no audit trail
- Business logic scattered across callbacks, controllers, and models with no single place to look

If several of those sound familiar, Railsmith gives you a single, consistent pattern for all of them. If they don't, you're probably not at the inflection point yet.

---

## The core idea

Every model access goes through a service. The service is the only place domain logic lives.

**Before** — logic split between controller and model, inconsistent error handling:

```ruby
# controller
def create
  @order = Order.new(order_params)
  @order.line_items.build(line_item_params)  # bypasses LineItem validations you care about
  if @order.save
    PaymentGateway.charge(@order)            # exception if it fails — now what?
    render json: @order, status: :created
  else
    render json: @order.errors, status: :unprocessable_entity
  end
end
```

**After** — one call, one result, everything in the right place:

```ruby
# controller
def create
  result = OrderService.call!(action: :create, params: order_params, context: ctx)
  render json: result.value, status: :created
end
# OrderService handles nested line items through LineItemService (hooks, validations intact),
# payment charging, rollback on failure, and returns a structured Result — no rescue needed.
```

---

## Installation

```ruby
# Gemfile
gem "railsmith"
```

```bash
bundle install
rails generate railsmith:install
```

The install generator creates `config/initializers/railsmith.rb` and the `app/services/` directory tree.

---

## Quick Start

Generate a service for a model:

```bash
rails generate railsmith:model_service User
```

Call it:

```ruby
result = UserService.call(
  action: :create,
  params: { attributes: { name: "Alice", email: "alice@example.com" } }
)

if result.success?
  puts result.value.id
else
  puts result.error.message   # => "Validation failed"
  puts result.error.details   # => { errors: { email: ["is invalid"] } }
end
```

See [docs/quickstart.md](docs/quickstart.md) for a full walkthrough.

---

## Examples (Sample App + Smoke Scripts)

For runnable examples that exercise `Railsmith::Pipeline` and services the way a small app would (without shipping a full Rails skeleton in this gem repo), see the companion repository:

- **`railsmith_sample`**: [`github.com/samaswin/railsmith_sample`](https://github.com/samaswin/railsmith_sample)

It includes smoke scripts for checkout pipelines and async nested writes against both in-process and real queue backends (Redis/Postgres/RabbitMQ).

---


## Declarative Inputs

Declare expected parameters with types, defaults, and constraints using the `input` DSL. Railsmith coerces, validates, and filters params automatically before the action runs.

```ruby
class UserService < Railsmith::BaseService
  model User
  domain :identity

  input :email,    String,   required: true, transform: ->(v) { v.strip.downcase }
  input :age,      Integer,  default: nil
  input :role,     String,   in: %w[admin member guest], default: "member"
  input :active,   :boolean, default: true
  input :metadata, Hash,     default: -> { {} }
end
```

- **Type coercion** — strings to integers, booleans, dates, and more
- **Validation** — required fields, allowed value lists, coercion failures all return structured `validation_error` results
- **Input filtering** — only declared keys reach the action (mass-assignment protection)
- **Inheritance** — subclasses inherit parent inputs and can extend or override independently

See [docs/inputs.md](docs/inputs.md) for the full reference.

---

## Association Support

Declare associations at the service level for eager loading, nested CRUD, and cascading destroy. Nested writes delegate to each associated service class — so every service's input validation, lifecycle hooks, and custom logic run as if you had called that service directly.

```ruby
class OrderService < Railsmith::BaseService
  model Order
  domain :commerce

  has_many   :line_items,   service: LineItemService, dependent: :destroy
  has_many   :audit_events, service: AuditEventService, async: true
  belongs_to :customer,     service: CustomerService, optional: true

  includes :line_items, :customer
end
```

**Nested create** — pass associated records in `params`; the foreign key is injected automatically:

```ruby
OrderService.call(
  action: :create,
  params: {
    attributes: { total: 99.99, customer_id: 7 },
    line_items: [
      { attributes: { product_id: 1, qty: 2, price: 29.99 } }
    ]
  },
  context: ctx
)
```

By default, nested writes run in the parent's transaction; any failure rolls back everything. Associations declared with `async: true` enqueue a background job **after** the parent commits instead — see [Async nested writes](docs/associations.md#async-nested-writes).

See [docs/associations.md](docs/associations.md) for the full reference (including `dependent:` modes and async configuration).

---

## Service Pipelines

Chain multiple services into a sequential workflow with fail-fast semantics, automatic param forwarding, rollback/compensation, conditional steps, and built-in instrumentation.

```ruby
class CheckoutPipeline < Railsmith::Pipeline
  domain :commerce

  step :validate_cart,     service: CartService,         action: :validate
  step :reserve_inventory, service: InventoryService,    action: :reserve,
                           rollback: :unreserve
  step :charge_payment,    service: PaymentService,      action: :charge,
                           inputs: { amount: :cart_total }, rollback: :refund
  step :create_order,      service: OrderService,        action: :create
  step :send_confirmation, service: NotificationService, action: :send_receipt,
                           on_failure_continue: true
end

result = CheckoutPipeline.call(params: { cart_id: 42, user_id: 7 }, context: ctx)
result.meta[:pipeline_step]  # => :charge_payment (on failure)
```

Each step's Hash `result.value` is merged into accumulated params so the next step receives all data gathered so far. On failure, completed steps are rolled back in reverse order. Conditional steps (`if:` / `unless:`) are skipped cleanly without affecting the rollback sequence.

See [docs/pipelines.md](docs/pipelines.md) for the full reference.

---

## Lifecycle Hooks

Attach `before`, `after`, and `around` callbacks to any service action for cross-cutting concerns — audit logging, event publishing, metrics, authorization:

```ruby
class OrderService < Railsmith::BaseService
  model Order

  before :create, :update, :destroy, name: :audit_log do
    AuditLog.record(actor: context[:actor_id], service: self.class.name)
  end

  after :create do |result|
    EventBus.publish("order.created", result.value) if result.success?
  end

  around :charge do |action|
    Metrics.time("order.charge") { action.call }
  end
end
```

Apply hooks globally across all services (or all services in a domain) via `Railsmith.configure`:

```ruby
Railsmith.configure do |config|
  config.before_action :create do
    RateLimiter.check!(context[:actor_id])
  end

  config.around_action :charge, only: [:commerce] do |action|
    CommerceSandbox.wrap { action.call }
  end
end
```

See [docs/hooks.md](docs/hooks.md) for the full reference.

---

## Result Chaining

Compose services without a full pipeline using the fluent Result API:

```ruby
result = CartService.call(action: :validate, params: { cart_id: 42 }, context: ctx)
  .and_then { |data| PaymentService.call(action: :charge, params: data, context: ctx) }
  .and_then { |data| OrderService.call(action: :create, params: data, context: ctx) }
  .on_success { |data| EventBus.publish("order.created", data) }
  .on_failure { |err|  ErrorTracker.capture(err) }
```

| Method | Fires when | Returns |
|--------|-----------|---------|
| `and_then { \|value\| }` | Success only | Chained Result |
| `or_else { \|error\| }` | Failure only | Chained Result |
| `on_success { \|value\| }` | Success only | `self` (side-effect) |
| `on_failure { \|error\| }` | Failure only | `self` (side-effect) |

---

## `call!` — Raising Variant

`call!` raises `Railsmith::Failure` instead of returning a failure result. Use it in controllers with `rescue_from`:

```ruby
class ApplicationController < ActionController::API
  include Railsmith::ControllerHelpers
  # Catches Railsmith::Failure and renders JSON with the correct HTTP status
end

class UsersController < ApplicationController
  def create
    result = UserService.call!(action: :create, params: { attributes: user_params }, context: ctx)
    render json: result.value, status: :created
  end
end
```

`Railsmith::Failure` carries the full structured result for inspection in rescue handlers:

```ruby
rescue Railsmith::Failure => e
  e.code    # => "validation_error"
  e.result  # => Railsmith::Result (failure)
end
```

See [docs/call-bang.md](docs/call-bang.md) for the full reference.

---

## Generators

| Command | Output |
|---------|--------|
| `rails g railsmith:install` | Initializer + service directories |
| `rails g railsmith:domain Billing` | `app/domains/billing.rb` + subdirectories |
| `rails g railsmith:model_service User` | `app/services/user_service.rb` |
| `rails g railsmith:model_service User --inputs` | Service with `input` DSL (introspects model columns) |
| `rails g railsmith:model_service Order --associations` | Service with association DSL (introspects model associations) |
| `rails g railsmith:model_service Billing::Invoice --domain=Billing` | `app/domains/billing/services/invoice_service.rb` |
| `rails g railsmith:operation Billing::Invoices::Create` | `app/domains/billing/invoices/create.rb` |
| `rails g railsmith:pipeline Checkout` | `app/pipelines/checkout_pipeline.rb` + spec |
| `rake railsmith:pipelines` | List all pipeline classes and their declared steps |

---

## CRUD Actions

CRUD defaults exist to make domain enforcement practical. If every model access must go through a service — so arch checks, cross-domain guards, and lifecycle hooks fire consistently — you'd otherwise hand-write boilerplate services for every model. The defaults give you a compliant service for free; override only what needs custom logic.

Services that declare a `model` inherit `create`, `update`, `destroy`, `find`, and `list` with automatic exception mapping:

```ruby
class UserService < Railsmith::BaseService
  model(User)
end

# create (context: is optional from 1.1 onward)
UserService.call(action: :create, params: { attributes: { email: "a@b.com" } })

# update
UserService.call(action: :update, params: { id: 1, attributes: { email: "new@b.com" } })

# destroy
UserService.call(action: :destroy, params: { id: 1 })
```

Common ActiveRecord exceptions (`RecordNotFound`, `RecordInvalid`, `RecordNotUnique`) are caught and converted to structured failure results automatically.

---

## Bulk Operations

```ruby
# bulk_create
UserService.call(
  action: :bulk_create,
  params: {
    items: [{ name: "Alice", email: "a@b.com" }, { name: "Bob", email: "b@b.com" }],
    transaction_mode: :best_effort  # or :all_or_nothing
  }
)

# bulk_update
UserService.call(
  action: :bulk_update,
  params: { items: [{ id: 1, attributes: { name: "Alice Smith" } }] }
)

# bulk_destroy
UserService.call(
  action: :bulk_destroy,
  params: { items: [1, 2, 3] }
)
```

All bulk results include a `summary` (`total`, `success_count`, `failure_count`, `all_succeeded`) and per-item detail. See [docs/cookbook.md](docs/cookbook.md) for the full result shape.

---

## Domain Boundaries

Tag services with a bounded context and track it through all calls:

```bash
rails generate railsmith:domain Billing
rails generate railsmith:model_service Billing::Invoice --domain=Billing
```

```ruby
module Billing
  module Services
    class InvoiceService < Railsmith::BaseService
      model(Billing::Invoice)
      domain :billing
    end
  end
end
```

Pass context when you need domain or tracing data (`context:` is optional; omit it to use thread-local `Context.current` or an auto-built context):

```ruby
ctx = Railsmith::Context.new(domain: :billing, request_id: "req-abc")

Billing::Services::InvoiceService.call(action: :create, params: { ... }, context: ctx)
```

### Request ID (`X-Request-Id`)

If you omit `request_id`, Railsmith auto-generates one — which does **not** match the `X-Request-Id` header ActionDispatch exposes on the request. To align service instrumentation with your load balancer or upstream caller, pass the request id from the controller.

Include `Railsmith::ControllerHelpers` and use `railsmith_context` (it sets `request_id` from `request.request_id`):

```ruby
class OrdersController < ApplicationController
  include Railsmith::ControllerHelpers

  def create
    result = OrderService.call!(
      action: :create,
      params: { attributes: order_params },
      context: railsmith_context(domain: :commerce, actor_id: current_user.id)
    )
    render json: result.value, status: :created
  end
end
```

You can also set context once per request with `Railsmith::Context.with` (for example in `around_action`), including `request_id: request.request_id`, so every service call without an explicit `context:` inherits it. See [docs/call-bang.md](docs/call-bang.md#request-id-and-railsmith_context).

When the context domain differs from a service's declared `domain`, Railsmith emits a `cross_domain.warning.railsmith` instrumentation event. The payload includes `log_json_line` and `log_kv_line` (from `Railsmith::CrossDomainWarningFormatter`) for structured logging; when `strict_mode` is true, `on_cross_domain_violation` receives the same payload.

Configure enforcement in `config/initializers/railsmith.rb`:

```ruby
Railsmith.configure do |config|
  config.warn_on_cross_domain_calls = true   # default
  config.strict_mode = false
  config.on_cross_domain_violation = ->(payload) { ... }
  config.cross_domain_allowlist = [{ from: :catalog, to: :billing }]

  # Required if any association uses async: true (see docs/associations.md)
  # config.async_job_class = Railsmith::AsyncNestedWriteJob
end
```

---

## Error Types

| Code | Factory |
|------|---------|
| `validation_error` | `Railsmith::Errors.validation_error(message:, details:)` |
| `not_found` | `Railsmith::Errors.not_found(message:, details:)` |
| `conflict` | `Railsmith::Errors.conflict(message:, details:)` |
| `unauthorized` | `Railsmith::Errors.unauthorized(message:, details:)` |
| `unexpected` | `Railsmith::Errors.unexpected(message:, details:)` |

---

## Architecture Checks

Detect controllers that access models directly (and related service-layer rules). From the shell:

```bash
rake railsmith:arch_check
RAILSMITH_FORMAT=json rake railsmith:arch_check
RAILSMITH_FAIL_ON_ARCH_VIOLATIONS=true rake railsmith:arch_check
```

From Ruby (same environment variables and exit codes as the task), after `require "railsmith/arch_checks"`:

```ruby
Railsmith::ArchChecks::Cli.run # => 0 or 1
```

See [Migration](MIGRATION.md#embedding-architecture-checks-from-ruby) for optional `env:`, `output:`, and `warn_proc:` arguments.

---

## Documentation

- [Quickstart](docs/quickstart.md) — install, generate, first call
- [Inputs](docs/inputs.md) — declarative input DSL, type coercion, filtering, custom coercions
- [Associations](docs/associations.md) — association DSL, eager loading, nested CRUD, cascading destroy, async nested writes
- [Pipelines](docs/pipelines.md) — sequential service composition, param forwarding, rollback, conditional steps, instrumentation
- [Hooks](docs/hooks.md) — before/after/around DSL, conditional hooks, inheritance, global hooks, introspection
- [Pipelines (guides path)](docs/guides/pipelines.md) / [Hooks (guides path)](docs/guides/hooks.md) — stubs linking to the canonical guides above
- [call!](docs/call-bang.md) — raising variant, controller integration, `ControllerHelpers`, `railsmith_context` / request IDs
- [Cookbook](docs/cookbook.md) — CRUD, bulk, inputs, associations, domain context, error mapping, observability
- [Legacy Adoption Guide](docs/legacy-adoption.md) — incremental migration strategy
- [Migration](MIGRATION.md) — upgrading from any 1.x release
- [Changelog](CHANGELOG.md)

---

## Development

```bash
bin/setup       # install dependencies
bundle exec rake spec   # run tests
bin/console     # interactive prompt
```

### Multi-Rails matrix (Appraisal)

Appraisal gemfiles live under [`gemfiles/`](gemfiles/). After `bundle install`, generate or refresh lockfiles with `bundle exec appraisal install`. Run the suite against each combination:

```bash
bundle exec appraisal rails-7-0 rake spec
bundle exec appraisal rails-8-0 rake spec
# or: bundle exec appraisal rake spec   # runs the default task for each gemfile
```

To reproduce one cell without the Appraisal CLI:

```bash
BUNDLE_GEMFILE=gemfiles/rails_7_0.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/rails_7_0.gemfile bundle exec rspec
```

### Benchmark (optional)

- `ruby benchmarks/pipeline_overhead.rb` — coarse timing of pipeline vs sequential calls (see script header).

To install locally: `bundle exec rake install`.

---

## Contributing

Bug reports and pull requests are welcome at [github.com/samaswin/railsmith](https://github.com/samaswin/railsmith).

## License

[MIT License](https://opensource.org/licenses/MIT).
