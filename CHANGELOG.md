# Changelog

All notable changes to Railsmith are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Added — Declarative Inputs & Type Coercion

- **`input` DSL** — declare expected parameters with types, defaults, and constraints directly on any `BaseService` subclass:

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

- **`Railsmith::BaseService::InputDefinition`** — frozen value object storing each input's `name`, `type`, `required`, `default` (static value or zero-arg lambda), `in_values`, and `transform`.

- **`Railsmith::BaseService::InputRegistry`** — ordered collection of `InputDefinition`s attached to a service class; deep-duped on inheritance so subclasses can extend or override without affecting the parent.

- **`Railsmith::BaseService::TypeCoercion`** — automatic type conversion before validation. Supported target types and strategies:

  | Type | Behaviour |
  |------|-----------|
  | `String` | `value.to_s` |
  | `Integer` | `Integer(value)` — strict; non-numeric strings produce `validation_error` |
  | `Float` | `Float(value)` — strict |
  | `BigDecimal` | `BigDecimal(value.to_s)` |
  | `:boolean` | `"true"/"1"/true → true`, `"false"/"0"/false → false`; other values error |
  | `Date` | `Date.parse(value.to_s)` |
  | `DateTime` | `DateTime.parse(value.to_s)` |
  | `Time` | `Time.parse(value.to_s)` |
  | `Symbol` | `value.to_sym` |
  | `Array` | `Array(value)` — wraps scalars |
  | `Hash` | passthrough; non-hash values produce `validation_error` |

- **`Railsmith::BaseService::InputResolver`** — single-pass pipeline that runs on every `call` when inputs are declared:
  1. Apply defaults for missing keys
  2. Coerce types
  3. Validate required fields
  4. Validate `in:` constraints
  5. Apply `transform:` procs
  6. Filter undeclared keys (security: prevents mass-assignment of unexpected fields)

- **`filter_inputs false`** class-level opt-out — disables undeclared key filtering when needed. Inherited by subclasses.

- **`transform:` option on `input`** — optional zero-arg Proc applied after coercion (e.g. `transform: ->(v) { v.strip.downcase }`).

- **Custom coercions** — register arbitrary type coercers globally:

  ```ruby
  Railsmith.configure do |c|
    c.register_coercion(:money, ->(v) { Money.new(v) })
  end
  ```

- **`Configuration#register_coercion` / `#custom_coercions`** — storage and lookup for custom type coercers.

- **Input scoping** — when a `model` is declared, inputs describe `params[:attributes]`; for custom (non-model) actions, inputs describe the top-level `params` hash.

- **Inheritance** — subclasses inherit all parent inputs and can add or override them independently.

### Added — `call!` Variant & Error Enhancements

- **`BaseService.call!`** — raising variant of `call`. Identical signature; raises `Railsmith::Failure` instead of returning a failure `Result`. Intended for controller contexts that use `rescue_from`:

  ```ruby
  # Raises on any failure result; returns the Result on success.
  UserService.call!(action: :create, params: params, context: ctx)
  ```

- **`Railsmith::Failure`** — `StandardError` subclass wrapping a failure `Result`. Carries the original structured error so `rescue` / `rescue_from` handlers can inspect it without parsing a string:

  ```ruby
  rescue Railsmith::Failure => e
    e.result   # => Railsmith::Result (failure)
    e.code     # => "validation_error"
    e.error    # => Railsmith::Errors::ErrorPayload
    e.meta     # => {}
    e.message  # => human-readable error message from the payload
  end
  ```

- **`Railsmith::ControllerHelpers`** — `ActiveSupport::Concern` for Rails controllers. Include it once in `ApplicationController` to get automatic JSON error responses mapped to standard HTTP statuses:

  ```ruby
  class ApplicationController < ActionController::API
    include Railsmith::ControllerHelpers
  end
  ```

  Status mapping:

  | Error code | HTTP status |
  |---|---|
  | `validation_error` | 422 Unprocessable Entity |
  | `not_found` | 404 Not Found |
  | `conflict` | 409 Conflict |
  | `unauthorized` | 401 Unauthorized |
  | `unexpected` | 500 Internal Server Error |
  | _(unknown)_ | 500 Internal Server Error |

  The rendered JSON body is `result.to_h` — same shape as every other Railsmith failure response.

### Added — Association Support

- **`has_many` / `has_one` / `belongs_to` DSL** — declare associations directly on a service class:

  ```ruby
  class OrderService < Railsmith::BaseService
    model Order
    domain :commerce

    has_many   :line_items,       service: LineItemService, dependent: :destroy
    has_one    :shipping_address, service: AddressService,  dependent: :nullify
    belongs_to :customer,         service: CustomerService, optional: true
  end
  ```

- **`Railsmith::BaseService::AssociationDefinition`** — frozen value object per association, storing `name`, `kind` (`:has_many`, `:has_one`, `:belongs_to`), `service_class`, `foreign_key`, `dependent`, `optional`, and `validate`.

- **`Railsmith::BaseService::AssociationRegistry`** — ordered collection of `AssociationDefinition`s; deep-duped on inheritance so subclasses extend associations without affecting parents.

- **`Railsmith::BaseService::AssociationDsl`** — provides the `has_many`, `has_one`, and `belongs_to` class macros. Foreign keys are auto-inferred when not given:
  - `has_many` / `has_one`: FK is `"#{parent_model_name.underscore}_id"` on the child (e.g. `order_id`)
  - `belongs_to`: FK is `"#{association_name}_id"` on this record (e.g. `customer_id`)

- **`includes` DSL** (`Railsmith::BaseService::EagerLoading`) — declare eager loads at the class level; multiple calls are additive:

  ```ruby
  class OrderService < Railsmith::BaseService
    model Order

    includes :line_items, :customer
    includes line_items: [:product, :variant]
  end
  ```

  Declared loads are applied automatically in `find` and `list` (via the `base_scope` helper). Custom action overrides are unaffected.

- **`Railsmith::BaseService::NestedWriter`** — handles nested association writes within the parent's open transaction:

  - **Nested create** — pass nested records under the association key in `params`; the FK is injected automatically:

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

  - **Nested update** — per-item semantics driven by the presence of `id` and `_destroy`:

    | Item shape | Action |
    |---|---|
    | `{ id:, attributes: }` | update via child service |
    | `{ attributes: }` (no `id`) | create via child service (FK injected) |
    | `{ id:, _destroy: true }` | destroy via child service |

  - **Cascading destroy** — controlled by the `dependent:` option on the association:

    | Option | Behaviour |
    |---|---|
    | `:destroy` | calls child service `destroy` for each associated record |
    | `:nullify` | calls child service `update` with FK set to `nil` |
    | `:restrict` | returns `validation_error` failure if any children exist |
    | `:ignore` | does nothing (default; relies on DB-level constraints) |

  All nested operations run within the parent's transaction — any failure triggers a full rollback of both parent and nested writes.

- **Association-aware `bulk_create`** — bulk items now support the nested format alongside the existing flat format:

  ```ruby
  # Flat (existing, unchanged)
  items: [{ name: "A" }, { name: "B" }]

  # Nested (new)
  items: [
    { attributes: { total: 50.00 }, line_items: [{ attributes: { product_id: 1, qty: 1 } }] },
    { attributes: { total: 75.00 }, line_items: [{ attributes: { product_id: 2, qty: 1 } }] }
  ]
  ```

  When no associations are declared the bulk format and behavior are identical to 1.1.0.

### Added — Generator Updates

- **`--inputs` flag on `railsmith:model_service`** — generates `input` DSL declarations in the scaffolded service. Two modes:

  - **Auto-introspect** (`--inputs` with no values): reads `Model.columns_hash` and emits one `input` declaration per non-system column (`id`, `created_at`, `updated_at` are excluded). Requires the model to be loaded at generation time; prints a warning and skips gracefully when it isn't.
  - **Explicit** (`--inputs=email:string:required name:string age:integer`): generates the listed inputs without touching the model. Format per spec: `name:type[:required]`.

  Supported type tokens and their mapped Ruby types:

  | Token | Ruby type |
  |---|---|
  | `string`, `text` | `String` |
  | `integer`, `bigint` | `Integer` |
  | `float` | `Float` |
  | `decimal` | `BigDecimal` |
  | `boolean` | `:boolean` |
  | `date` | `Date` |
  | `datetime`, `timestamp` | `DateTime` |
  | `time` | `Time` |
  | `json`, `jsonb`, `hstore` | `Hash` |
  | _(unknown)_ | `String` |

- **`--associations` flag on `railsmith:model_service`** — introspects `Model.reflect_on_all_associations` and emits `has_many`, `has_one`, and `belongs_to` declarations plus an `includes` line covering all associations. Prints a warning and skips when the model can't be loaded. Adds `# TODO: Define XxxService` comments for associated service classes that are not yet defined.

- **Updated `model_service.rb.tt` template** — renders optional `# -- Inputs --` and `# -- Associations --` sections when the respective flags are used. Sections are omitted entirely when the flags are absent, preserving the existing output for services generated without them.

### Deprecated

- `required_keys:` keyword on `validate()` — emits a deprecation warning at runtime. Migrate to the `input` DSL with `required: true`. The parameter continues to work for services that do not use the `input` DSL.

### Fixed

- Architecture checker `MissingServiceUsageChecker` recognizes flat domain operation calls (e.g. `Billing::Invoices::Create.call`) without an `Operations::` segment, matching the 1.1.0 generator defaults.
- `ArchReport` text footer and JSON summary reflect fail-on vs warn-only mode (`fail_on_arch_violations`).

### Changed

- `railsmith:install` creates `app/services` only (no empty `app/services/operations/`).
- Cross-domain warning payloads include `log_json_line` and `log_kv_line` from `CrossDomainWarningFormatter`.

---

## [1.1.0] — 2026-03-30

### Added

- Appraisal-style gemfiles for CI and local testing: `gemfiles/rails_7.gemfile` and `gemfiles/rails_8.gemfile` (with lockfiles), pinning `activerecord` / `railties` to Rails 7.x and 8.x respectively.
- `--namespace` flag on `railsmith:model_service` and `railsmith:operation` generators.
  Wraps the generated class in the given modules (e.g. `--namespace=Billing::Services`).
  When a namespace is provided on `model_service`, `domain` is automatically set from its first segment.
  Pass `--namespace=Operations` explicitly to match the pre-1.1 default layout.
- `Railsmith::Context` — canonical context value object (replaces `Railsmith::DomainContext` for new code).
  Accepts `domain:` (preferred) and arbitrary top-level keyword args (`actor_id:`, `request_id:`, etc.) without a nested `:meta` hash.
  `#[]` accessor, `#blank_domain?`, `#to_h` (backward-compatible shape: `{ current_domain: ..., **extras }`).
- `Context#request_id` — auto-generated UUID (`SecureRandom.uuid`) when no `request_id:` is supplied; explicit values always win (e.g. `X-Request-Id`).
- `Context.build(value)` — coerces context-like values into a `Context` (`Context` as-is, hash with `:domain` / `:current_domain`, or `nil`/`{}` for a minimal context with auto `request_id`).
- `Railsmith::Context.current` and `Railsmith::Context.with(**kwargs, &block)` — thread-local context for the request scope; nested blocks restore the previous value.
- `domain` DSL on `BaseService` subclasses — preferred alias for `service_domain` (aligned with `Context`’s `domain:` kwarg).
- `find` and `list` actions on model-backed services — `find` returns `Result.success(value: record)` or `not_found`; `list` defaults to `model_class.all` (override for filtering).

### Changed

- `railsmith:model_service MODEL` — default output is `app/services/<model>_service.rb` with **no module wrapper** (was `app/services/operations/<model>_service.rb` in `module Operations`). Existing code is unaffected.
- `railsmith:operation NAME` — default hierarchy is `<Domain>::…::<Operation>` without an interstitial `Operations` module (was `.../operations/...` on disk and in module nesting). Use `--namespace=Operations` for the old layout.
- `Railsmith::BaseService::ContextPropagation` — renamed from `DomainContextPropagation`; reads both `:current_domain` and `:domain` for compatibility.
- `context:` on `BaseService.call` is **optional**; omitting it, or passing `nil`/`{}`, yields a real `Context` with an auto `request_id` (no `ArgumentError`).
- `BaseService.call` context resolution: explicit `context:` > thread-local `Context.current` > auto-built empty context.
- **Ruby**: minimum supported version is **>= 3.1.0** (was >= 3.2.0). RuboCop `TargetRubyVersion` is aligned to 3.1.
- `Railsmith::Context` implementation: `.with` / `.build` use `thread_context_from` and `build_from_hash` as `private_class_method`s; `#[]` uses `%i[current_domain domain]` for domain lookup (behavior unchanged).
- Packaged gem file list: `gemfiles/`, `.ruby-version`, and `.tool-versions` excluded from the gem tarball.

### Deprecated

- `Railsmith::DomainContext` — deprecation warning on `.new`; removed in a future major release. Use `Railsmith::Context`.
- `current_domain:` on `Context.new` — use `domain:` (warning when used).
- `service_domain` on `BaseService` — use `domain` (warning when used); removed in a future major release.

### Fixed

- Removed obsolete `Style/ArgumentsForwarding` RuboCop disables in bulk helpers (`bulk_actions`, `bulk_execution`).
- `activerecord` is an explicit runtime dependency (`>= 7.0, < 9.0`); avoids opaque `NoMethodError` when CRUD/bulk run outside a full Rails load.
- Root `Gemfile` pins `connection_pool`, `nokogiri`, `erb`, and `zeitwerk` under `RUBY_VERSION < "3.2"`, matching `gemfiles/rails_7.gemfile`, so Ruby 3.1 resolves without forcing `BUNDLE_GEMFILE`.
- `railsmith:operation` — `initialize` uses `Railsmith::Context.build(context)` instead of `deep_dup` on context; frozen `Context` instances work; generated stub uses `context[:domain]` only.
- `railsmith:model_service` — domain mode no longer emits `_service.rb` when the model name omits the domain prefix; generator comments reference `domain`, not `service_domain`.

### Development

- GitHub Actions **CI**: lint (RuboCop, Ruby 3.3); test matrix Ruby 3.1–3.3 × Rails 7/8 gemfiles (Ruby 3.1 excluded with Rails 8). `permissions: contents: read`, `fail-fast: false`, `ruby/setup-ruby` `gemfile:` for installs.
- `railsmith:model_service` generator: file-level `Metrics/ClassLength` RuboCop disable/enable around `ModelServiceGenerator` only.

---

## [1.0.0] — 2026-03-29

First stable release. Public DSL and result contract are now frozen.

### Added

#### Core
- `Railsmith::Result` — immutable value object with `success?`, `failure?`, `value`, `error`, `code`, `meta`, and `to_h`.
- `Railsmith::Errors` — normalized error builders: `validation_error`, `not_found`, `conflict`, `unauthorized`, `unexpected`.
- `Railsmith::BaseService` — lifecycle entrypoint `call(action:, params:, context:)` with deterministic hook ordering and subclass override points.

#### CRUD
- Default `create`, `update`, and `destroy` actions on any service that declares `model(ModelClass)`.
- Automatic exception mapping: `ActiveRecord::RecordNotFound` → `not_found`, `ActiveRecord::RecordInvalid` → `validation_error`, `ActiveRecord::RecordNotUnique` → `conflict`.
- Safe record lookup helper with consistent not-found failure shape.

#### Bulk Operations
- `bulk_create`, `bulk_update`, `bulk_destroy` on model-backed services.
- Per-item result aggregation with batch `summary` (`total`, `success_count`, `failure_count`, `all_succeeded`).
- Transaction modes: `:all_or_nothing` (rollback on any failure) and `:best_effort` (commit successful items).
- Configurable batch size limit.

#### Domain Context
- `Railsmith::DomainContext` — carries `current_domain` and arbitrary `meta` through a call chain.
- `service_domain :name` declaration on `BaseService` subclasses.
- Context propagation guard: emits `cross_domain.warning.railsmith` ActiveSupport instrumentation event when context domain differs from service domain.
- Allowlist configuration for approved cross-domain crossings.
- `on_cross_domain_violation` callback hook for custom handling.

#### Architecture Checks
- `Railsmith::ArchChecks::DirectModelAccessChecker` — static analysis for controllers that access models directly.
- `Railsmith::ArchChecks::MissingServiceUsageChecker` — flags controller actions that touch models without calling a service-style entrypoint.
- Text and JSON report formatters (`Railsmith::ArchReport`).
- `Railsmith::ArchChecks::Cli` — Ruby API for the same scan as `railsmith:arch_check`, with optional `env:`, `output:`, and `warn_proc:` for tests and embedding.
- `rake railsmith:arch_check` task with `RAILSMITH_PATHS`, `RAILSMITH_FORMAT`, and `RAILSMITH_FAIL_ON_ARCH_VIOLATIONS` environment variable support; the task delegates to `Railsmith::ArchChecks::Cli.run` (same report shape and exit semantics for callers).

#### Generators
- `railsmith:install` — creates `config/initializers/railsmith.rb` and `app/services/` directory tree.
- `railsmith:domain NAME` — scaffolds a domain module skeleton with conventional subdirectories.
- `railsmith:model_service MODEL` — scaffolds a `BaseService` subclass, namespace-aware with `--domain` flag.
- `railsmith:operation NAME` — scaffolds a plain-Ruby operation with `call` entrypoint returning `Railsmith::Result`.

#### Configuration
- `Railsmith.configure` block with: `warn_on_cross_domain_calls`, `strict_mode`, `on_cross_domain_violation`, `cross_domain_allowlist`, `fail_on_arch_violations`.

#### Documentation
- [Quickstart](docs/quickstart.md)
- [Cookbook](docs/cookbook.md) — CRUD, bulk, domain context, error mapping, observability
- [Legacy Adoption Guide](docs/legacy-adoption.md) — incremental migration strategy

---

## [0.1.0] — pre-release

Internal bootstrap release. Gem skeleton, CI baseline, and initial service scaffolding. Not intended for production use.

[Unreleased]: https://github.com/samaswin/railsmith/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/samaswin/railsmith/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/samaswin/railsmith/releases/tag/v1.0.0
