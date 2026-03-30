# Railsmith Cookbook

Recipes for common patterns. Each section is self-contained.

---

## CRUD

### Default CRUD with no customization

```bash
rails generate railsmith:model_service Post
```

```ruby
# app/services/post_service.rb
class PostService < Railsmith::BaseService
  model(Post)
end
```

The five default actions work immediately (`context:` is optional on all calls):

```ruby
# Create
result = PostService.call(
  action: :create,
  params: { attributes: { title: "Hello", body: "World" } }
)

# Update
result = PostService.call(
  action: :update,
  params: { id: 1, attributes: { title: "Updated" } }
)

# Destroy
result = PostService.call(action: :destroy, params: { id: 1 })

# Find a single record by ID
result = PostService.call(action: :find, params: { id: 1 })
result.value  # => <Post id=1>

# List all records
result = PostService.call(action: :list, params: {})
result.value  # => [<Post>, ...]
```

---

### Customizing attribute extraction

Override `sanitize_attributes` to strip or transform attributes before the record is written:

```ruby
class PostService < Railsmith::BaseService
  model(Post)

  private

  def sanitize_attributes(attributes)
    attributes.except(:admin_override, :internal_flag)
  end
end
```

Override `attributes_params` to change where attributes are read from:

```ruby
def attributes_params
  params[:post]  # instead of params[:attributes]
end
```

---

### Custom finder logic

```ruby
class PostService < Railsmith::BaseService
  model(Post)

  private

  def find_record(model_klass, id)
    model_klass.published.find_by(id: id)
  end
end
```

### Filtering list results

Override `list` to apply scopes or filters:

```ruby
class PostService < Railsmith::BaseService
  model(Post)

  def list
    posts = Post.where(published: params[:published]).order(:created_at)
    Result.success(value: posts)
  end
end
```

---

### Custom action

Define a method with the action name. Use `Result` and `Errors` directly:

```ruby
class PostService < Railsmith::BaseService
  model(Post)

  def publish
    id = params[:id]
    return Result.failure(error: Errors.validation_error(details: { missing: ["id"] })) unless id

    post = Post.find_by(id: id)
    return Result.failure(error: Errors.not_found(message: "Post not found", details: { id: id })) unless post

    return Result.failure(error: Errors.conflict(message: "Already published")) if post.published?

    post.update!(published_at: Time.current)
    Result.success(value: post)
  end
end
```

Call it the same way:

```ruby
result = PostService.call(action: :publish, params: { id: 42 })
```

---

### Chaining service calls

Pass `context` through to preserve domain tracking:

```ruby
class OrderService < Railsmith::BaseService
  model(Order)

  def place
    # Validate stock via another service
    stock_result = InventoryService.call(
      action: :reserve,
      params: { sku: params[:sku], qty: params[:qty] },
      context: context  # forward the same context
    )
    return stock_result if stock_result.failure?

    OrderService.call(
      action: :create,
      params: { attributes: { sku: params[:sku], qty: params[:qty] } },
      context: context
    )
  end
end
```

Alternatively, use thread-local context propagation (see [Thread-local context](#thread-local-context-propagation)) so you don't need to thread `context:` through every call.

---

## Bulk Operations

### bulk_create

```ruby
result = UserService.call(
  action: :bulk_create,
  params: {
    items: [
      { name: "Alice", email: "alice@example.com" },
      { name: "Bob",   email: "bob@example.com" }
    ]
  },
  context: {}
)

summary = result.value[:summary]
# => { total: 2, success_count: 2, failure_count: 0, all_succeeded: true }

result.value[:items].each do |item|
  if item[:success]
    puts "Created #{item[:value].id}"
  else
    puts "Failed item #{item[:index]}: #{item[:error][:message]}"
  end
end
```

---

### bulk_update

Each item must include an `id` key and an `attributes` key:

```ruby
result = UserService.call(
  action: :bulk_update,
  params: {
    items: [
      { id: 1, attributes: { name: "Alice Smith" } },
      { id: 2, attributes: { name: "Bob Jones"  } }
    ]
  },
  context: {}
)
```

---

### bulk_destroy

Pass IDs directly or as hashes:

```ruby
# Array of IDs
result = UserService.call(
  action: :bulk_destroy,
  params: { items: [1, 2, 3] },
  context: {}
)

# Array of hashes
result = UserService.call(
  action: :bulk_destroy,
  params: { items: [{ id: 1 }, { id: 2 }] },
  context: {}
)
```

---

### Transaction modes

| Mode | Behavior |
|------|----------|
| `:best_effort` (default) | Each item in its own transaction. Partial success is persisted. |
| `:all_or_nothing` | All items in one transaction. Any failure rolls back the entire batch. |

```ruby
# All-or-nothing import
result = UserService.call(
  action: :bulk_create,
  params: {
    items: rows,
    transaction_mode: :all_or_nothing,
    limit: 500,
    batch_size: 50
  },
  context: {}
)

unless result.value[:summary][:all_succeeded]
  # Roll back handled automatically; inspect failures:
  result.value[:items].select { |i| !i[:success] }.each do |i|
    puts "Row #{i[:index]}: #{i[:error][:message]}"
  end
end
```

---

### Bulk result shape

```ruby
result.value
# {
#   operation:        "bulk_create",
#   transaction_mode: "best_effort",
#   items: [
#     { index: 0, input: {...}, success: true,  value: <User>, error: nil    },
#     { index: 1, input: {...}, success: false, value: nil,    error: {...}  }
#   ],
#   summary: {
#     total:          2,
#     success_count:  1,
#     failure_count:  1,
#     all_succeeded:  false
#   }
# }

result.meta
# { model: "User", operation: "bulk_create", transaction_mode: "best_effort", limit: 1000 }
```

---

## Domain Context and Boundaries

### Declare a domain

```bash
rails generate railsmith:domain Billing
```

Creates `app/domains/billing.rb` and subdirectories `app/domains/billing/operations/` and `app/domains/billing/services/`.

```bash
rails generate railsmith:model_service Billing::Invoice --domain=Billing
```

Creates `app/domains/billing/services/invoice_service.rb`:

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

---

### Pass domain context on a call

Use `Railsmith::Context` to attach domain and tracing data. Extra keys (`actor_id`, `request_id`, etc.) are top-level — no nested `:meta` hash:

```ruby
ctx = Railsmith::Context.new(
  domain: :billing,
  actor_id: current_user.id
  # request_id is auto-generated as a UUID when omitted
)

result = Billing::Services::InvoiceService.call(
  action: :create,
  params: { attributes: { amount: 100_00, currency: "USD" } },
  context: ctx
)
```

To forward an existing request ID (e.g. from an HTTP header):

```ruby
ctx = Railsmith::Context.new(
  domain: :billing,
  request_id: request.headers["X-Request-Id"],
  actor_id: current_user.id
)
```

---

### Thread-local context propagation

Set context once at the edge of a request instead of threading it through every call:

```ruby
# app/controllers/application_controller.rb
around_action do |_, block|
  Railsmith::Context.with(domain: :web, actor_id: current_user&.id) { block.call }
end
```

Services automatically inherit the thread-local context when no explicit `context:` is passed:

```ruby
# No context: needed — picked up from Context.with above
UserService.call(action: :create, params: { attributes: { name: "Alice" } })
```

Resolution order: **explicit `context:` arg > `Context.current` > auto-built context**.

`Context.with` restores the previous value after the block, making it safe for nested calls and concurrent requests.

---

### Cross-domain detection

When the context domain differs from a service's declared `domain`, Railsmith emits a warning. By default this is non-blocking.

```ruby
# context says :catalog, service declares :billing — warning fires
result = Billing::Services::InvoiceService.call(
  action: :create,
  params: { ... },
  context: { current_domain: :catalog }
)
```

Subscribe to cross-domain warnings for logging:

```ruby
Railsmith::Instrumentation.subscribe("cross_domain.warning.railsmith") do |_event, payload|
  Rails.logger.warn("[cross-domain] #{payload.inspect}")
end
```

---

### Configure domain enforcement

```ruby
# config/initializers/railsmith.rb
Railsmith.configure do |config|
  # Warn on all cross-domain calls (default: true)
  config.warn_on_cross_domain_calls = true

  # Strict mode: run a custom hook on every violation
  config.strict_mode = true
  config.on_cross_domain_violation = ->(payload) {
    Honeybadger.notify("Cross-domain call", context: payload)
  }

  # Allowlist known approved cross-domain pairs
  config.cross_domain_allowlist = [
    { from: :catalog, to: :billing },
    [:shipping, :inventory]
  ]
end
```

Allowlisted pairs do not emit warnings.

---

### Generate a domain operation

```bash
rails generate railsmith:operation Billing::Invoices::Finalize
```

Creates `app/domains/billing/invoices/finalize.rb`:

```ruby
module Billing
  module Invoices
    class Finalize
      def self.call(params: {}, context: {})
        new(params:, context:).call
      end

      attr_reader :params, :context

      def initialize(params:, context:)
        @params = Railsmith.deep_dup(params || {})
        @context = Railsmith::Context.build(context)
      end

      def call
        Railsmith::Result.success(value: {})
      end
    end
  end
end
```

To keep the old `Operations` interstitial module:

```bash
rails generate railsmith:operation Billing::Invoices::Finalize --namespace=Operations
# => app/domains/billing/operations/invoices/finalize.rb
# => Billing::Operations::Invoices::Finalize
```

---

## Error Mapping

### Error types

| Code | Factory method | Typical trigger |
|------|---------------|-----------------|
| `validation_error` | `Errors.validation_error(...)` | ActiveModel validation failure |
| `not_found` | `Errors.not_found(...)` | `find_by` returns nil |
| `conflict` | `Errors.conflict(...)` | Duplicate unique constraint |
| `unauthorized` | `Errors.unauthorized(...)` | Permission check fails |
| `unexpected` | `Errors.unexpected(...)` | Unhandled exception |

---

### Building errors manually

```ruby
# Validation
error = Railsmith::Errors.validation_error(
  message: "Validation failed",
  details: { errors: { email: ["is invalid"], name: ["can't be blank"] } }
)

# Not found
error = Railsmith::Errors.not_found(
  message: "Invoice not found",
  details: { model: "Invoice", id: 99 }
)

# Conflict
error = Railsmith::Errors.conflict(
  message: "Email already taken",
  details: { field: "email" }
)

# Unauthorized
error = Railsmith::Errors.unauthorized(
  message: "Admin access required",
  details: { required_role: "admin" }
)

# Unexpected
error = Railsmith::Errors.unexpected(
  message: "Stripe API unavailable",
  details: { exception_class: "Stripe::APIConnectionError" }
)

# Wrap in a Result
result = Railsmith::Result.failure(error: error)
```

---

### Automatic exception mapping (built into default CRUD)

The default `create`, `update`, and `destroy` actions catch and map these exceptions automatically — you don't need to rescue them yourself:

| Exception | Mapped code |
|-----------|-------------|
| `ActiveRecord::RecordNotFound` | `not_found` |
| `ActiveRecord::RecordInvalid` | `validation_error` (with `record.errors`) |
| `ActiveRecord::RecordNotUnique` | `conflict` |
| `ActiveRecord::StaleObjectError` | `conflict` |
| Any other exception | `unexpected` |

---

### Consuming errors in a controller

```ruby
class UsersController < ApplicationController
  def create
    result = UserService.call(
      action: :create,
      params: { attributes: user_params },
      context: Railsmith::Context.new(domain: :identity)
    )

    if result.success?
      render json: result.value, status: :created
    else
      status = case result.code
               when "validation_error" then :unprocessable_entity
               when "not_found"        then :not_found
               when "conflict"         then :conflict
               when "unauthorized"     then :forbidden
               else                         :internal_server_error
               end
      render json: result.error.to_h, status: status
    end
  end

  private

  def user_params
    params.require(:user).permit(:name, :email)
  end
end
```

---

### Inline validation with required keys

```ruby
def register
  val = validate(params, required_keys: [:email, :password])
  return val if val.failure?

  # ... proceed
end
```

`validate` returns `Result.failure` with a `validation_error` if any key is missing, or `Result.success` otherwise.

---

## Observability

### Subscribe to service call events

```ruby
Railsmith::Instrumentation.subscribe("service.call.railsmith") do |_event, payload|
  Rails.logger.info(
    "[railsmith] #{payload[:service]}##{payload[:action]} domain=#{payload[:domain]}"
  )
end
```

### Subscribe to cross-domain warnings

```ruby
Railsmith::Instrumentation.subscribe("cross_domain.warning.railsmith") do |_event, payload|
  Rails.logger.warn("[railsmith:cross-domain] #{payload.inspect}")
end
```

---

## Architecture Checks

Run static analysis to find controllers directly touching models (and actions missing service usage, per the bundled checkers):

```bash
rake railsmith:arch_check
```

With options:

```bash
# JSON output
RAILSMITH_FORMAT=json rake railsmith:arch_check

# Check additional paths
RAILSMITH_PATHS=app/controllers,app/jobs rake railsmith:arch_check

# Fail CI on violations
RAILSMITH_FAIL_ON_ARCH_VIOLATIONS=true rake railsmith:arch_check
```

The Rake task wraps `Railsmith::ArchChecks::Cli.run`. Use that when you need the same scan in Ruby (for example, to capture output or run with a custom env hash):

```ruby
require "railsmith/arch_checks"
require "stringio"

out = StringIO.new
status = Railsmith::ArchChecks::Cli.run(
  env: ENV.to_h.merge("RAILSMITH_PATHS" => "app/controllers", "RAILSMITH_FORMAT" => "json"),
  output: out
)
# status is 0 or 1; report body is out.string
```

Or set the default fail-on behaviour in the initializer:

```ruby
Railsmith.configure do |config|
  config.fail_on_arch_violations = true
end
```
