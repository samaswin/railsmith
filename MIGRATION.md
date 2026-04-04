# Migration Guide

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
