# Migration Guide

## Upgrading from 0.x (pre-release) to 1.0.0

Railsmith 1.0.0 is the first stable release. If you were using the 0.x development version, the changes below are required before upgrading.

---

### Requirements

| | 0.x | 1.0.0 |
|---|---|---|
| Ruby | >= 3.2.0 | >= 3.2.0 |
| Rails | 7.0–8.x | 7.0–8.x |

No changes to minimum runtime requirements.

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

| Generator | Output path (1.0.0) |
|-----------|---------------------|
| `railsmith:model_service User` | `app/services/operations/user_service.rb` |
| `railsmith:model_service Billing::Invoice --domain=Billing` | `app/domains/billing/services/invoice_service.rb` |
| `railsmith:operation Billing::Invoices::Create` | `app/domains/billing/operations/invoices/create.rb` |

---

### Initializer — new configuration keys

Add any missing keys to `config/initializers/railsmith.rb`. All keys have safe defaults so omitting them will not raise, but explicit configuration is recommended.

```ruby
Railsmith.configure do |config|
  config.warn_on_cross_domain_calls = true   # default: true
  config.strict_mode = false                  # default: false (reserved for v1.2)
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
