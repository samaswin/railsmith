# Railsmith

Railsmith is a service-layer gem for Rails. It standardizes domain-oriented service boundaries with sensible defaults for CRUD operations, bulk operations, result handling, and cross-domain enforcement.

**Requirements**: Ruby >= 3.1.0, Rails 7.0–8.x

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

## Result Contract

Every service call returns a `Railsmith::Result`. You never rescue exceptions from service calls.

```ruby
# Success
result = Railsmith::Result.success(value: { id: 123 }, meta: { request_id: "abc" })
result.success?  # => true
result.value     # => { id: 123 }
result.meta      # => { request_id: "abc" }
result.to_h      # => { success: true, value: { id: 123 }, meta: { request_id: "abc" } }

# Failure
error  = Railsmith::Errors.not_found(message: "User not found", details: { model: "User", id: 1 })
result = Railsmith::Result.failure(error:)
result.failure?        # => true
result.code            # => "not_found"
result.error.to_h      # => { code: "not_found", message: "User not found", details: { ... } }
```

---

## Generators

| Command | Output |
|---------|--------|
| `rails g railsmith:install` | Initializer + service directories |
| `rails g railsmith:domain Billing` | `app/domains/billing.rb` + subdirectories |
| `rails g railsmith:model_service User` | `app/services/user_service.rb` |
| `rails g railsmith:model_service Billing::Invoice --domain=Billing` | `app/domains/billing/services/invoice_service.rb` |
| `rails g railsmith:operation Billing::Invoices::Create` | `app/domains/billing/invoices/create.rb` |

---

## CRUD Actions

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

When the context domain differs from a service's declared `domain`, Railsmith emits a `cross_domain.warning.railsmith` instrumentation event. The payload includes `log_json_line` and `log_kv_line` (from `Railsmith::CrossDomainWarningFormatter`) for structured logging; when `strict_mode` is true, `on_cross_domain_violation` receives the same payload.

Configure enforcement in `config/initializers/railsmith.rb`:

```ruby
Railsmith.configure do |config|
  config.warn_on_cross_domain_calls = true   # default
  config.strict_mode = false
  config.on_cross_domain_violation = ->(payload) { ... }
  config.cross_domain_allowlist = [{ from: :catalog, to: :billing }]
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
- [Cookbook](docs/cookbook.md) — CRUD, bulk, domain context, error mapping, observability
- [Legacy Adoption Guide](docs/legacy-adoption.md) — incremental migration strategy
- [Migration](MIGRATION.md) — upgrading from 1.0.x to 1.1.x (and earlier releases)
- [Changelog](CHANGELOG.md)

---

## Development

```bash
bin/setup       # install dependencies
bundle exec rake spec   # run tests
bin/console     # interactive prompt
```

CI runs the suite against Rails 7 and Rails 8 using [`gemfiles/rails_7.gemfile`](gemfiles/rails_7.gemfile) and [`gemfiles/rails_8.gemfile`](gemfiles/rails_8.gemfile) (Ruby 3.1–3.3; Rails 8 is not paired with Ruby 3.1 in CI). To reproduce a matrix cell locally:

```bash
BUNDLE_GEMFILE=gemfiles/rails_7.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/rails_7.gemfile bundle exec rspec
```

To install locally: `bundle exec rake install`.

### Releasing

With `lib/railsmith/version.rb` and `CHANGELOG.md` updated and committed, run `bundle exec rake release` to tag `v` + version, build the gem, and push to RubyGems (requires `gem push` credentials and a clean git state). To publish manually: `gem build railsmith.gemspec` then `gem push railsmith-X.Y.Z.gem`.

---

## Contributing

Bug reports and pull requests are welcome at [github.com/samaswin/railsmith](https://github.com/samaswin/railsmith).

## License

[MIT License](https://opensource.org/licenses/MIT).
