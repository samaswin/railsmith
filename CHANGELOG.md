# Changelog

All notable changes to Railsmith are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Added

- Appraisal-style gemfiles for CI and local testing: `gemfiles/rails_7.gemfile` and `gemfiles/rails_8.gemfile` (with lockfiles), pinning `activerecord` / `railties` to Rails 7.x and 8.x respectively.
- `--namespace` flag on `railsmith:model_service` and `railsmith:operation` generators.
  Wraps the generated class in the given modules (e.g. `--namespace=Billing::Services`).
  When a namespace is provided, `service_domain` is automatically set from its first segment.
  Generators that previously required `--namespace=Operations` to match the old default can now pass that flag explicitly.

### Changed

- `railsmith:model_service MODEL` — default output is now `app/services/<model>_service.rb` with **no module wrapper**.
  Previously generated `app/services/operations/<model>_service.rb` inside `module Operations`.
  Existing generated services are unaffected; the old namespace continues to work.
- `railsmith:operation NAME` — default module hierarchy is now `<Domain>::<Operation>` with **no interstitial `Operations` module**.
  Previously generated `<Domain>::Operations::<Operation>` and placed files under `.../operations/...`.
  Existing generated operations are unaffected; pass `--namespace=Operations` to restore the old structure.

- `Railsmith::Context` — replaces `Railsmith::DomainContext` as the canonical context value object.
  Accepts `domain:` (preferred) and arbitrary top-level keyword args (`actor_id:`, `request_id:`, etc.) without a nested `:meta` hash.
  `#[]` accessor, `#blank_domain?`, `#to_h` (backward-compatible shape: `{ current_domain: ..., **extras }`).
- `Railsmith::BaseService::ContextPropagation` — renamed internal module (was `DomainContextPropagation`).
  Reads both `:current_domain` and `:domain` context keys for compatibility.
- `Context#request_id` — auto-generated UUID (`SecureRandom.uuid`) assigned at construction when no `request_id:` is supplied.
  Passing an explicit `request_id:` value always takes precedence (e.g. forwarding an `X-Request-Id` header).

- `Context.build(value)` factory on `Railsmith::Context` — coerces any context-like value into a `Context`:
  - Already a `Context` → returned as-is.
  - A hash with `:domain` or `:current_domain` → wrapped in `Context.new(**hash)` (all extra keys forwarded).
  - `nil` or `{}` → builds a minimal `Context` with an auto-generated `request_id`.
- `context:` argument to `BaseService.call` is now optional. Omitting it (or passing `nil`/`{}`) produces
  a real `Context` with a `request_id`; no `ArgumentError` is raised.
- `find` action on model-backed services — returns `Result.success(value: record)` or a `not_found` failure.
- `list` action on model-backed services — returns `Result.success(value: model_class.all)` by default; meant to be overridden when filtering is required.
- `Railsmith::Context.current` — returns the thread-local `Context` (or `nil` when none is set).
- `Railsmith::Context.with(**kwargs, &block)` — sets a thread-local context for the duration of the block, then restores the previous value. Safe for concurrent use.
- `domain` DSL method on `BaseService` subclasses — equivalent to `service_domain` (shorter, consistent with the `domain:` kwarg on `Context`).

### Changed

- `BaseService.call` context resolution order: explicit `context:` arg > thread-local `Context.current` > auto-built empty context.
- **Ruby**: minimum supported version is now **>= 3.1.0** (was >= 3.2.0). RuboCop `TargetRubyVersion` is aligned to 3.1.
- `Railsmith::Context` — refactored `.with` and `.build` helpers: `thread_context_from` and `build_from_hash` as `private_class_method`s; `#[]` uses `%i[current_domain domain]` for domain lookup (behavior unchanged).
- Packaged gem file list: `gemfiles/`, `.ruby-version`, and `.tool-versions` are excluded from the gem tarball (development-only paths).

### Development

- GitHub Actions workflow renamed to **CI**; **lint** job runs RuboCop on Ruby 3.3; **test** matrix runs RSpec and the arch-check smoke task across Ruby **3.1**, **3.2**, and **3.3** with `BUNDLE_GEMFILE` set to each Rails gemfile (Ruby **3.1** is excluded with Rails 8 — same constraint as upstream Rails). `permissions: contents: read`, `fail-fast: false` on tests, `ruby/setup-ruby` `gemfile:` for matrix installs.
- `railsmith:model_service` generator: file-level `Metrics/ClassLength` RuboCop disable/enable around `ModelServiceGenerator` only.

### Fixed

- Removed obsolete `Style/ArgumentsForwarding` RuboCop disable comments in bulk operation helpers (`bulk_actions`, `bulk_execution`) now that the targeted Ruby/RuboCop configuration no longer requires them.

### Deprecated

- `Railsmith::DomainContext` — still works but emits a deprecation warning on every `.new` call.
  Will be removed in the next major release. Replace with `Railsmith::Context`.
- `current_domain:` keyword on `Context.new` — use `domain:` instead.
  Emits a deprecation warning when used.
- `service_domain` DSL method on `BaseService` subclasses — use `domain` instead.
  Emits a deprecation warning when used. Will be removed in the next major release.

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
