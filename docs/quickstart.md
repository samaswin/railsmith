# Railsmith Quickstart

## 1. Install

Add to your `Gemfile`:

```ruby
gem "railsmith"
```

Then:

```bash
bundle install
```

**Requirements**: Ruby >= 3.1.0, Rails 7.0–8.x.

---

## 2. Generate the Initializer

```bash
rails generate railsmith:install
```

This creates:

- `config/initializers/railsmith.rb` — global configuration
- `app/services/` and `app/services/operations/` — service directories

The generated initializer:

```ruby
# config/initializers/railsmith.rb
Railsmith.configure do |config|
  config.warn_on_cross_domain_calls = true
  config.strict_mode = false
  config.fail_on_arch_violations = false
end
```

---

## 3. Generate Your First Service

```bash
rails generate railsmith:model_service User
```

Creates `app/services/user_service.rb`:

```ruby
class UserService < Railsmith::BaseService
  model(User)
end
```

The `model` declaration wires up the default CRUD actions (`create`, `update`, `destroy`, `find`, `list`) and the three bulk actions (`bulk_create`, `bulk_update`, `bulk_destroy`) automatically — no extra code needed for standard cases.

To generate under a namespace, pass `--namespace`:

```bash
rails generate railsmith:model_service User --namespace=Operations
# => app/services/operations/user_service.rb
# => module Operations; class UserService
```

---

## 4. Make Your First Call

```ruby
result = UserService.call(
  action: :create,
  params: { attributes: { name: "Alice", email: "alice@example.com" } }
)

if result.success?
  puts "Created user #{result.value.id}"
else
  puts "Failed: #{result.error.message}"
  puts result.error.details.inspect
end
```

Every service call returns a `Railsmith::Result`. You never rescue exceptions from service calls — failures surface as structured `Result` objects.

`context:` is optional. When omitted, Railsmith builds a context automatically (with an auto-generated `request_id`). Pass one explicitly to attach domain, actor, or tracing data:

```ruby
UserService.call(
  action: :create,
  params: { attributes: { name: "Alice", email: "alice@example.com" } },
  context: Railsmith::Context.new(domain: :identity, actor_id: current_user.id)
)
```

In controllers, auto-generated `request_id` values do not match the HTTP `X-Request-Id` / `request.request_id` that ActionDispatch sets. After `include Railsmith::ControllerHelpers`, use `railsmith_context(...)` so services share the same id as your load balancer or upstream caller, or set `Railsmith::Context.with(..., request_id: request.request_id)` once per request — see [call! / ControllerHelpers](call-bang.md#request-id-and-railsmith_context).

---

## 5. Result Contract at a Glance

```ruby
# Success
result.success?  # => true
result.value     # => the returned object (e.g., an ActiveRecord instance)
result.meta      # => optional hash of metadata
result.to_h
# => { success: true, value: ..., meta: ... }

# Failure
result.failure?  # => true
result.code      # => "not_found" | "validation_error" | "conflict" | "unauthorized" | "unexpected"
result.error     # => Railsmith::Errors::ErrorPayload
result.error.message   # => human-readable string
result.error.details   # => structured hash (model errors, missing keys, etc.)
result.error.to_h      # => { code: ..., message: ..., details: ... }
```

---

## 6. Next Steps

- **[Cookbook](cookbook.md)** — CRUD customization, bulk operations, domain context, thread-local context, error mapping, custom actions.
- **[Associations](associations.md)** — nested CRUD, `dependent:` modes, optional async nested writes.
- **[Legacy Adoption Guide](legacy-adoption.md)** — Incrementally migrate an existing Rails app to Railsmith.
- **[Migration Guide](../MIGRATION.md)** — Upgrade notes between releases.
