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

**Requirements**: Ruby >= 3.2.0, Rails 7.0–8.x.

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

Creates `app/services/operations/user_service.rb`:

```ruby
module Operations
  class UserService < Railsmith::BaseService
    model(User)
  end
end
```

The `model` declaration wires up the three default CRUD actions (`create`, `update`, `destroy`) and the three bulk actions (`bulk_create`, `bulk_update`, `bulk_destroy`) automatically — no extra code needed for standard cases.

---

## 4. Make Your First Call

```ruby
result = Operations::UserService.call(
  action: :create,
  params: { attributes: { name: "Alice", email: "alice@example.com" } },
  context: {}
)

if result.success?
  puts "Created user #{result.value.id}"
else
  puts "Failed: #{result.error.message}"
  puts result.error.details.inspect
end
```

Every service call returns a `Railsmith::Result`. You never rescue exceptions from service calls — failures surface as structured `Result` objects.

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

- **[Cookbook](cookbook.md)** — CRUD customization, bulk operations, domain context, error mapping, custom actions.
- **[Legacy Adoption Guide](legacy-adoption.md)** — Incrementally migrate an existing Rails app to Railsmith.
