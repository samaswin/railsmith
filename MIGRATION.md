# Migration Guide

## Upgrading from 1.1.0 to 1.2.0

All changes in 1.2.0 are **additive and backward-compatible**. Every service written for 1.1.0 continues to work without modification.

---

### Input DSL (additive, replaces `required_keys:`)

The `input` class macro declares expected parameters with types, defaults, and constraints. It is entirely opt-in — services without `input` declarations behave identically to 1.1.0.

```ruby
class UserService < Railsmith::BaseService
  model User
  domain :identity

  input :email,    String,   required: true
  input :age,      Integer,  default: nil
  input :role,     String,   in: %w[admin member guest], default: "member"
  input :active,   :boolean, default: true
  input :metadata, Hash,     default: -> { {} }
end
```

When inputs are declared:

- Types are coerced automatically (string `"42"` → integer `42`, etc.)
- Required fields that are missing or `nil` return a `validation_error` result
- Only declared keys are forwarded to the action (undeclared keys are silently dropped)
- Defaults are applied before the action runs

**`required_keys:` is deprecated.** If you currently use `validate(params, required_keys: [:email])`, migrate to `input :email, String, required: true`. The `required_keys:` keyword continues to work but emits a deprecation warning. It will be removed in a future major release.

```ruby
# Before (deprecated, still works with warning)
def create
  val = validate(params, required_keys: [:email, :name])
  return val if val.failure?
  super
end

# After
input :email, String, required: true
input :name,  String, required: true
```

**No migration required.** Existing services are unaffected.

---

### `call!` and `ControllerHelpers` (additive)

`BaseService.call!` is a new class method with the same signature as `call`. It raises `Railsmith::Failure` instead of returning a failure result, for use in controllers that prefer `rescue_from`.

```ruby
# Raises Railsmith::Failure on any failure; returns Result on success
UserService.call!(action: :create, params: { attributes: user_params }, context: ctx)
```

`Railsmith::ControllerHelpers` is a new `ActiveSupport::Concern` for Rails controllers. Include it once in `ApplicationController` to handle all `Railsmith::Failure` exceptions with standard JSON responses and HTTP status codes:

```ruby
class ApplicationController < ActionController::API
  include Railsmith::ControllerHelpers
end
```

| Error code | HTTP status |
|------------|-------------|
| `validation_error` | 422 Unprocessable Entity |
| `not_found` | 404 Not Found |
| `conflict` | 409 Conflict |
| `unauthorized` | 401 Unauthorized |
| `unexpected` | 500 Internal Server Error |

Both `call!` and `ControllerHelpers` are entirely opt-in. All existing `call` usage is unaffected.

See [docs/call-bang.md](docs/call-bang.md) for detailed usage.

---

### Association DSL (additive)

`has_many`, `has_one`, and `belongs_to` are new class-level macros for declaring associations on a service. They are entirely opt-in — services without association declarations behave identically to 1.1.0.

```ruby
class OrderService < Railsmith::BaseService
  model Order
  domain :commerce

  has_many   :line_items,       service: LineItemService, dependent: :destroy
  has_one    :shipping_address, service: AddressService,  dependent: :nullify
  belongs_to :customer,         service: CustomerService, optional: true
end
```

**Options for `has_many` and `has_one`:**

| Option | Type | Default | Description |
|---|---|---|---|
| `service:` | Class | required | service class for the associated records |
| `foreign_key:` | Symbol | inferred | FK column on the child; inferred as `#{parent_model}_id` |
| `dependent:` | Symbol | `:ignore` | cascade behaviour on parent destroy (see Cascading Destroy below) |
| `validate:` | Boolean | `true` | validate nested records |

**Options for `belongs_to`:**

| Option | Type | Default | Description |
|---|---|---|---|
| `service:` | Class | required | service class for the parent record |
| `foreign_key:` | Symbol | inferred | FK column on this record; inferred as `#{association_name}_id` |
| `optional:` | Boolean | `false` | skip presence validation |

**No migration required.** Existing services are unaffected.

---

### Eager Loading DSL (additive)

The `includes` class macro declares eager loads applied automatically to `find` and `list`. Multiple calls are additive.

```ruby
class OrderService < Railsmith::BaseService
  model Order

  includes :line_items, :customer
  includes line_items: [:product, :variant]   # merged with the call above
end
```

Before adding `includes`, if you had a custom `find_record` override or a `list` override that applied its own `model_class.includes(...)`, those overrides are **unaffected** — the default `base_scope` applies only to the built-in `find` and `list` actions.

If your custom action already calls `find_record(model_klass, id)` it will now benefit from declared eager loads automatically. If this is unwanted, keep calling `model_klass.find_by(id:)` directly.

**No migration required.** Opt-in at your own pace.

---

### Nested Writes (additive)

When associations are declared, the `create` and `update` actions accept nested records under the association key in `params`. No change is required in services that do not pass nested params — the guards check `params` for association keys and skip silently when none are present.

#### Nested create

```ruby
OrderService.call(
  action: :create,
  params: {
    attributes: { total: 99.99, customer_id: 7 },
    line_items: [
      { attributes: { product_id: 1, qty: 2, price: 29.99 } },
      { attributes: { product_id: 5, qty: 1, price: 39.99 } }
    ],
    shipping_address: { attributes: { street: "123 Main St", city: "Portland" } }
  },
  context: ctx
)
```

The parent FK (`order_id`) is injected into each child's attributes automatically — you do not pass it.

All child writes run inside the parent's open transaction. Any failure rolls back the entire operation including the parent record.

#### Nested update

Pass nested items under the association key in `update` params. Per-item semantics:

| Item shape | Action taken |
|---|---|
| `{ id:, attributes: }` | update the existing child record |
| `{ attributes: }` (no `id`) | create a new child record (FK injected) |
| `{ id:, _destroy: true }` | destroy the child record |

```ruby
OrderService.call(
  action: :update,
  params: {
    id: 42,
    attributes: { total: 109.99 },
    line_items: [
      { id: 1, attributes: { qty: 3 } },        # update
      { attributes: { product_id: 9, qty: 1 } }, # create
      { id: 2, _destroy: true }                  # destroy
    ]
  },
  context: ctx
)
```

**No migration required.** Existing `update` calls without nested keys work exactly as before.

---

### Cascading Destroy (additive)

When `has_many` or `has_one` is declared with a `dependent:` option other than `:ignore`, the `destroy` action handles associated records through their service before deleting the parent.

| `dependent:` | Behaviour |
|---|---|
| `:destroy` | calls child service `destroy` for each associated record |
| `:nullify` | calls child service `update` with FK set to `nil` |
| `:restrict` | returns `validation_error` failure if any children exist (parent is not deleted) |
| `:ignore` | does nothing — default, matches 1.1.0 behaviour |

The default is `:ignore` so no existing `destroy` call changes behaviour unless you explicitly add a `dependent:` option to an association.

All cascading operations run inside the parent's transaction. Any failure rolls back the entire destroy.

---

### `bulk_create` — extended item format (backward-compatible)

`bulk_create` now accepts items in either the existing flat format or a new nested format when associations are declared.

```ruby
# Flat format — unchanged, still works exactly as before
items: [{ name: "A" }, { name: "B" }]

# Nested format — new, used when associations are declared
items: [
  { attributes: { total: 50.00 }, line_items: [{ attributes: { product_id: 1, qty: 1 } }] },
  { attributes: { total: 75.00 }, line_items: [{ attributes: { product_id: 2, qty: 1 } }] }
]
```

The two formats are detected automatically by the presence of an `attributes:` key in the item hash. Existing bulk calls using the flat format continue to work without any change.

---

### Upgrade steps for 1.1.0 → 1.2.0

1. Update `Gemfile`: `gem "railsmith", "~> 1.2"`
2. Run `bundle install`.
3. Run `bundle exec rspec` — all existing specs should pass with zero changes.
4. Opt-in to the `input` DSL on services where you want type coercion and validation (Phase 1, already available since the unreleased branch).
5. Opt-in to `has_many` / `has_one` / `belongs_to` on services that need nested writes or cascading destroy.
6. Opt-in to `includes` on services that need eager loading on `find` and `list`.
7. Deploy.

---

## Upgrading from 1.0.0 to 1.1.0

### Ruby >= 3.1 (non-breaking)

Railsmith **1.0.0** declared `required_ruby_version >= 3.2.0`. **1.1.0** lowers the minimum to **>= 3.1.0** so apps on Ruby 3.1 can depend on the gem without changing service code.

If you already run Ruby 3.2 or newer, no action is required.

---

### `DomainContext` → `Context` (non-breaking, deprecation warning)


`Railsmith::DomainContext` is deprecated in favour of `Railsmith::Context`. The old class still works but prints a deprecation warning on every `.new` call. It will be removed in the next major release.

#### New API at a glance

```ruby
# Before (1.0.0)
Railsmith::DomainContext.new(
  current_domain: :billing,
  meta: { request_id: "req-abc", actor_id: current_user.id }
)

# After (1.1.0)
Railsmith::Context.new(
  domain: :billing,
  actor_id: current_user.id   # top-level, no :meta wrapper
)
```

Key differences:

| | `DomainContext` (old) | `Context` (new) |
|---|---|---|
| Class | `Railsmith::DomainContext` | `Railsmith::Context` |
| Domain kwarg | `current_domain:` | `domain:` |
| Extra fields | nested under `meta:` | top-level kwargs |
| `to_h` shape | `{ current_domain:, **meta }` | same (unchanged) |

#### Migration steps

1. **Find all `DomainContext` usages:**
   ```
   grep -r "DomainContext" app/ spec/
   ```

2. **Replace the class name and kwargs:**
   ```ruby
   # Before
   ctx = Railsmith::DomainContext.new(current_domain: :billing, meta: { request_id: "r1", actor_id: 42 })

   # After
   ctx = Railsmith::Context.new(domain: :billing, request_id: "r1", actor_id: 42)
   ```

3. **If you read `ctx.meta` directly**, switch to individual readers:
   ```ruby
   ctx.meta[:actor_id]    # before
   ctx[:actor_id]         # after
   ```

4. **No changes needed at the call site.** `to_h` output is identical — services reading `context[:current_domain]` continue to work without modification.

#### Passing a context hash directly (unchanged)

Services that receive a plain hash (e.g. `context: { current_domain: :billing, actor_id: 42 }`) are unaffected. The hash shape is preserved by `Context#to_h`.

---

### Generator defaults — no forced namespace (non-breaking)

The `railsmith:model_service` and `railsmith:operation` generators no longer wrap generated classes in an `Operations::` module by default.

#### model_service generator

| | 1.0.0 default | 1.1.0 default |
|---|---|---|
| Command | `rails g railsmith:model_service User` | same |
| Output file | `app/services/operations/user_service.rb` | `app/services/user_service.rb` |
| Module wrapper | `module Operations` | none |
| Call site | `Operations::UserService.call(...)` | `UserService.call(...)` |

**Existing services are not broken** — any service already generated under `Operations::` continues to work without changes. The change only affects newly generated files.

To generate with an explicit namespace (e.g. when you want domain grouping):

```bash
rails generate railsmith:model_service Invoice --namespace=Billing::Services
# => app/services/billing/services/invoice_service.rb
# => module Billing; module Services; class InvoiceService
# => domain :billing  (auto-added from first segment)
```

To preserve the old `Operations::` default in a project that still wants it, pass `--namespace=Operations`:

```bash
rails generate railsmith:model_service User --namespace=Operations
# => app/services/operations/user_service.rb  (same as before)
```

#### operation generator

| | 1.0.0 default | 1.1.0 default |
|---|---|---|
| Command | `rails g railsmith:operation Billing::Invoices::Create` | same |
| Output file | `app/domains/billing/operations/invoices/create.rb` | `app/domains/billing/invoices/create.rb` |
| Module hierarchy | `Billing::Operations::Invoices::Create` | `Billing::Invoices::Create` |

**Existing operations are not broken** — files already under `.../operations/...` are unaffected.

To restore the old `Operations` interstitial module:

```bash
rails generate railsmith:operation Billing::Invoices::Create --namespace=Operations
# => app/domains/billing/operations/invoices/create.rb  (same as before)
```

---

### Auto-generated `request_id` (non-breaking)

`Railsmith::Context` now assigns a UUID `request_id` automatically at construction when one is not provided.

```ruby
ctx = Railsmith::Context.new(domain: :billing, actor_id: 42)
ctx.request_id  # => "550e8400-e29b-41d4-a716-446655440000"  (auto-generated)
ctx.to_h        # => { current_domain: :billing, actor_id: 42, request_id: "550e8400-..." }
```

To forward an existing request ID (e.g. from an incoming HTTP header), pass it explicitly — it is never overwritten:

```ruby
ctx = Railsmith::Context.new(domain: :web, request_id: request.headers["X-Request-Id"])
ctx.request_id  # => whatever the header contained
```

**No migration required.** All existing code that already passes `request_id:` continues to work unchanged. Code that omitted it now gets a UUID instead of `nil` in `to_h` — this is the intended behaviour.

If you have specs that assert `Context#to_h` equals an exact hash without a `request_id` key, update them to use `include(...)` or pass an explicit `request_id:` to fix the value:

```ruby
# Before (will fail — to_h now always includes request_id)
expect(ctx.to_h).to eq(current_domain: :billing, actor_id: 42)

# After — option A: assert on the keys you care about
expect(ctx.to_h).to include(current_domain: :billing, actor_id: 42)

# After — option B: fix the request_id to make equality deterministic
ctx = Railsmith::Context.new(domain: :billing, actor_id: 42, request_id: "r1")
expect(ctx.to_h).to eq(current_domain: :billing, actor_id: 42, request_id: "r1")
```

---

### `context:` is now optional at the call site (non-breaking)

`BaseService.call` no longer requires `context:`. Omitting it, passing `nil`, or passing `{}` all produce a valid `Context` with an auto-generated `request_id`.

```ruby
# All of these are equivalent and valid in 1.1.0
UserService.call(action: :create, params: { attributes: { name: "Alice" } })
UserService.call(action: :create, params: { ... }, context: {})
UserService.call(action: :create, params: { ... }, context: nil)
```

If you previously passed `context: {}` as a no-op placeholder, you can remove it — the behaviour is identical.

When you do pass a context value, `Context.build` handles coercion:

| Value passed | Result |
|---|---|
| A `Railsmith::Context` | used as-is |
| A hash with `:domain` or `:current_domain` | wrapped in `Context.new(**hash)` |
| `nil` or `{}` | new `Context` with auto `request_id` |

**No migration required.** Existing code that passes a full context is unaffected.

---

### New read actions: `find` and `list` (non-breaking, additive)

Two new CRUD actions are available on all model-backed services.

```ruby
# Find a single record by ID
result = UserService.call(action: :find, params: { id: 1 })
result.value  # => <User id=1>

# List all records (override to filter)
result = UserService.call(action: :list, params: {})
result.value  # => [<User>, ...]
```

Default `list` calls `model_class.all`. Override it when you need filtering:

```ruby
class UserService < Railsmith::BaseService
  model User

  def list
    users = User.where(active: params[:active]).order(:name)
    Result.success(value: users)
  end
end
```

**No migration required.** These are new methods; existing overrides are unaffected. If you had a custom `find` or `list` method that returns a different shape, it will shadow the default — check your override's return value matches `Result.success`/`Result.failure`.

---

### Thread-local context propagation (opt-in, non-breaking)

`Railsmith::Context.with(...)` sets a thread-local context for the duration of a block. Services automatically inherit it when no explicit `context:` is passed.

```ruby
# Set once at the edge (e.g. ApplicationController)
around_action do |_, block|
  Railsmith::Context.with(domain: :web, actor_id: current_user&.id) { block.call }
end

# Services pick it up automatically — no need to thread it through every call
UserService.call(action: :create, params: { ... })
```

Resolution order: **explicit `context:` arg > `Context.current` > auto-built empty context**.

Explicit `context:` always wins, so existing code that passes context explicitly is completely unaffected.

`Context.current` returns the current thread-local `Context` or `nil`. `Context.with` restores the previous value after the block, making it safe for nested calls and concurrent requests.

**No migration required.** This is fully opt-in.

---

### `service_domain` → `domain` DSL (non-breaking, deprecation warning)

The `service_domain` class macro is deprecated in favour of `domain`.

```ruby
# Before (1.0.0)
class InvoiceService < Railsmith::BaseService
  model Invoice
  service_domain :billing
end

# After (1.1.0)
class InvoiceService < Railsmith::BaseService
  model Invoice
  domain :billing
end
```

`service_domain` still works but emits a deprecation warning. It will be removed in the next major release.

#### Migration steps

```
grep -r "service_domain" app/
```

Replace each occurrence:

```ruby
service_domain :billing   # before
domain :billing           # after
```

---

## Upgrading from 0.x (pre-release) to 1.0.0

Railsmith 1.0.0 is the first stable release. If you were using the 0.x development version, the changes below are required before upgrading.

---

### Requirements

| | 0.x | 1.0.0 |
|---|---|---|
| Ruby | >= 3.2.0 | >= 3.2.0 |
| Rails | 7.0–8.x | 7.0–8.x |

No other changes to minimum runtime requirements at the 1.0.0 release. (Ruby **3.1** is supported starting in **1.1.0**; see the section above.)

---

### Result contract — now frozen

The `Railsmith::Result` interface is stable and will not change in any 1.x release.

**No action required** if you are already using the documented API (`success?`, `failure?`, `value`, `error`, `code`, `meta`, `to_h`).

If you were accessing any internal instance variables directly (e.g., `result.instance_variable_get(:@data)`), switch to the public API before upgrading.

---

### Error builders — keyword arguments required

All `Railsmith::Errors` factory methods now require keyword arguments.

```ruby
# Before (0.x, positional — no longer accepted)
Railsmith::Errors.not_found("User not found", { model: "User" })

# After (1.0.0)
Railsmith::Errors.not_found(message: "User not found", details: { model: "User" })
```

Both `message:` and `details:` are optional but must be passed as keywords when provided.

---

### `BaseService.call` — `context:` is now required

In 0.x, `context:` was optional and defaulted to `{}` silently. In 1.0.0, omitting `context:` raises `ArgumentError`.

```ruby
# Before (0.x — context omitted)
MyService.call(action: :create, params: { ... })

# After (1.0.0 — context required)
MyService.call(action: :create, params: { ... }, context: {})
```

Pass `context: {}` at minimum. Pass a `Railsmith::DomainContext` hash when using domain boundaries.

---

### Cross-domain warnings — ActiveSupport instrumentation only

In 0.x, cross-domain violations could be configured to write directly to `Rails.logger`. In 1.0.0, all violation events are emitted exclusively via ActiveSupport Instrumentation (`cross_domain.warning.railsmith`). Wire up your own subscriber if you need log output:

```ruby
# config/initializers/railsmith.rb
ActiveSupport::Notifications.subscribe("cross_domain.warning.railsmith") do |_name, _start, _finish, _id, payload|
  Rails.logger.warn("[Railsmith] cross-domain: #{payload.inspect}")
end
```

The `on_cross_domain_violation` config callback still fires and is the recommended place for custom handling.

---

### Generator output paths — finalized

Domain-scoped services are now always generated under `app/domains/<domain>/services/`. If you used the generator during 0.x development and accepted a different default path, move the files and update `require` paths accordingly.

| Generator | Output path (1.0.0) | Output path (1.1.0) |
|-----------|---------------------|---------------------|
| `railsmith:model_service User` | `app/services/operations/user_service.rb` | `app/services/user_service.rb` |
| `railsmith:model_service Billing::Invoice --domain=Billing` | `app/domains/billing/services/invoice_service.rb` | `app/domains/billing/services/invoice_service.rb` |
| `railsmith:operation Billing::Invoices::Create` | `app/domains/billing/operations/invoices/create.rb` | `app/domains/billing/invoices/create.rb` |

---

### Initializer — new configuration keys

Add any missing keys to `config/initializers/railsmith.rb`. All keys have safe defaults so omitting them will not raise, but explicit configuration is recommended.

```ruby
Railsmith.configure do |config|
  config.warn_on_cross_domain_calls = true   # default: true
  config.strict_mode = false                  # default: false; when true, +on_cross_domain_violation+ runs on each cross-domain call
  config.fail_on_arch_violations = false      # default: false
  config.cross_domain_allowlist = []          # default: []
  config.on_cross_domain_violation = nil      # default: nil (no-op)
end
```

---

### Bulk operations — transaction mode default

The default `transaction_mode` for bulk operations changed from `:best_effort` in 0.x to `:all_or_nothing` in 1.0.0.

If you rely on partial-success behavior, explicitly pass `transaction_mode: :best_effort`:

```ruby
MyService.call(
  action: :bulk_create,
  params: { items: [...], transaction_mode: :best_effort },
  context: {}
)
```

---

### Upgrade steps

1. Update `Gemfile`: `gem "railsmith", "~> 1.0"`
2. Run `bundle install`.
3. Run `bundle exec rspec` — fix any `ArgumentError` on `call` (add `context: {}`).
4. Search for positional `Railsmith::Errors.*` calls and convert to keywords.
5. Review initializer against the full key list above.
6. Run `rake railsmith:arch_check` as a smoke test.
7. Deploy.

---

## Embedding architecture checks from Ruby

You do not need this section for a normal upgrade. The `railsmith:arch_check` Rake task behaves the same from the shell (`RAILSMITH_PATHS`, `RAILSMITH_FORMAT`, `RAILSMITH_FAIL_ON_ARCH_VIOLATIONS`, and `Railsmith.configure { |c| c.fail_on_arch_violations }`).

If you maintain custom Rake tasks, CI scripts in Ruby, or tests that should run the same scan without shelling out, call the library entrypoint:

```ruby
require "railsmith/arch_checks"

status = Railsmith::ArchChecks::Cli.run
# 0 — success or warn-only; 1 — fail-on enabled and violations present

# Optional: isolated env, capture output, or custom warnings
# require "stringio"
# out = StringIO.new
# warnings = []
# status = Railsmith::ArchChecks::Cli.run(
#   env: { "RAILSMITH_PATHS" => "app/controllers", "RAILSMITH_FORMAT" => "text" },
#   output: out,
#   warn_proc: ->(message) { warnings << message }
# )
```

Replace `rake railsmith:arch_check` with `Cli.run` only when you explicitly need an in-process API; the task remains the supported default for apps.
