# Association Support

Railsmith provides first-class association handling on services: eager loading, nested creates and updates, optional **async** nested writes, and cascading destroy. Synchronous nested work runs in the parent’s transaction; async associations enqueue work after commit.

---

## Association DSL

Declare service relationships at the class level using `link_many`, `link_one`, and `link_ref`:

```ruby
class OrderService < Railsmith::BaseService
  model Order
  domain :commerce

  link_many   :line_items,   service: LineItemService, dependent: :destroy
  link_many   :audit_events, service: AuditEventService, async: true
  link_ref :customer,     service: CustomerService, optional: true
end
```

All three macros accept a `service:` option (required) pointing to the associated service class. Foreign keys are auto-inferred when not given.

### `link_many` / `link_one` options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `service:` | Class | required | service class for associated records |
| `foreign_key:` | Symbol | inferred | FK column on the child; defaults to `#{parent_model}_id` (e.g. `order_id`) |
| `dependent:` | Symbol | `:ignore` | cascade behaviour on parent destroy (see [Why `dependent:` exists](#why-dependent-exists)) |
| `validate:` | Boolean | `true` | validate nested records before writing |
| `async:` | Boolean | `false` | when `true`, nested writes for this association run in a background job after the parent commits ([details](#async-nested-writes)) |

### `link_ref` options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `service:` | Class | required | service class for the parent record |
| `foreign_key:` | Symbol | inferred | FK on this record; defaults to `#{association_name}_id` (e.g. `customer_id`) |
| `optional:` | Boolean | `false` | skip presence validation for the FK |

`link_ref` does not support `async:` (the referenced row must exist before the FK is written).

---

## Why `dependent:` exists

`dependent:` on `link_many` / `link_one` controls what happens to child records when the **parent** is destroyed. Without it, destroying a parent can leave orphaned rows unless the database enforces `ON DELETE CASCADE` (or similar).

Railsmith’s `dependent:` is service-layer compensation: child work runs **through the associated service**, so child callbacks, hooks, events, and audit paths still run, and cascading destroy stays inside the parent’s transaction (failures roll back with the parent).

| `dependent:` | Behaviour |
|----------------|-----------|
| `:destroy` | child service `destroy` for each associated record |
| `:restrict` | `validation_error` if any children exist (parent is not deleted) |
| `:ignore` | nothing — rely on DB constraints (default) |

`async: true` is **not** compatible with `:destroy` or `:restrict`, because deferred jobs cannot safely participate in the same transaction as parent destroy.

---

## Eager loading

The `includes` class macro declares eager loads applied automatically via `base_scope` (used by the built-in `find_record` helper and the default `list` action). Multiple calls are additive:

```ruby
class OrderService < Railsmith::BaseService
  model Order

  includes :line_items, :customer
  includes line_items: [:product, :variant]   # merged with the call above
end
```

You can scope eager loads to specific actions:

```ruby
class OrderService < Railsmith::BaseService
  model Order

  includes :customer
  includes :line_items, only: %i[find list]
  includes :audit_events, except: %i[list]
end
```

Declared loads go through `base_scope` — custom action overrides that call `find_record` directly will also benefit automatically. If you call `model_klass.find_by(id:)` directly in a custom action, those eager loads will not apply (by design).

---

## Nested create

Pass nested records under the association key in `params`. The parent FK is injected automatically — you do not pass it.

```ruby
OrderService.call(
  action: :create,
  params: {
    attributes: { total: 99.99, customer_id: 7 },
    line_items: [
      { attributes: { product_id: 1, qty: 2, price: 29.99 } },
      { attributes: { product_id: 5, qty: 1, price: 39.99 } }
    ],
    shipping_address: {
      attributes: { street: "123 Main St", city: "Portland", zip: "97201" }
    }
  },
  context: ctx
)
```

**Transaction behavior:** for synchronous associations, all child writes run inside the parent's open transaction. Any failure (parent or child) rolls back the entire operation. For `async: true` associations, the parent commits first; the nested write runs later in a job (see [Async nested writes](#async-nested-writes)).

### Result shape for nested create

```ruby
result.value   # => the parent record (with associations loaded)
result.meta    # => {
               #      nested: {
               #        line_items:       { total: 2, success_count: 2, failure_count: 0 },
               #        shipping_address: { success: true }
               #      }
               #    }
```

---

## Nested update

Pass nested items under the association key in `params`. Per-item semantics are driven by the presence of `id` and `_destroy`:

| Item shape | Action taken |
|------------|-------------|
| `{ id:, attributes: }` | update the existing child via child service |
| `{ attributes: }` (no `id`) | create a new child via child service (FK injected) |
| `{ id:, _destroy: true }` | destroy the child via child service |

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

For synchronous associations, all nested operations run within the parent's transaction — any failure triggers a full rollback. Async associations do not block the parent on child success.

---

## Async nested writes

Mark a `link_many` or `link_one` relationship with `async: true` to **enqueue** nested creates/updates as a background job **after** the parent transaction commits, instead of running inline.

### Configuration

Set an ActiveJob class on the global configuration (required whenever `async: true` is used):

```ruby
# config/initializers/railsmith.rb
Railsmith.configure do |config|
  config.async_job_class = Railsmith::AsyncNestedWriteJob
end
```

If `async_job_class` is missing, nested writes raise `Railsmith::AsyncNotConfiguredError`.

The gem ships with `Railsmith::AsyncNestedWriteJob`, which re-hydrates the parent service, rebuilds `Context` from the serialized hash, and re-runs the nested write for the given association. You may subclass or replace it as long as the job’s `perform` contract matches what `enqueue_nested_write` passes (`service_class`, `association`, `parent_id`, `nested_params`, `mode`, `context`).

### Semantics

| Concern | Sync (default) | Async (`async: true`) |
|---------|----------------|------------------------|
| Runs inside parent transaction | Yes | No — job runs after commit |
| Parent waits for children | Yes | No |
| Child failure rolls back parent | Yes | No |
| Child failure handling | Result failure → full rollback | ActiveJob retries / dead-lettering |

### When to use `async: true`

- Audit events, analytics, notifications — work that should not block the HTTP response or roll back the parent if it fails.
- Large fan-out where enqueueing is cheaper than holding one transaction open.

### When not to use `async: true`

- Core data that must stay consistent with the parent (for example order line items).
- Associations with `dependent: :destroy` or `:restrict` (disallowed at declaration time).
- Any case where you need the parent and children to succeed or fail together in one transaction.

### Instrumentation

Railsmith emits:

| Event | When |
|-------|------|
| `nested_write.enqueued.railsmith` | After the job is enqueued; payload includes `association`, `parent_id`, `job_id`, `mode`, `service` |
| `async_nested_write.failed.railsmith` | When the job rescues an exception before re-raising (can fire on each failed attempt until the job succeeds or is discarded; pair with your job backend’s retry/DLQ settings) |

Subscribe via `Railsmith::Instrumentation.subscribe` or `ActiveSupport::Notifications`.

---

## Cascading destroy

When `link_many` or `link_one` is declared with a `dependent:` option, the `destroy` action handles associated records through their service before deleting the parent.

| `dependent:` | Behaviour |
|--------------|-----------|
| `:destroy` | calls child service `destroy` for each associated record |
| `:restrict` | returns `validation_error` failure if any children exist (parent is not deleted) |
| `:ignore` | does nothing — default, relies on DB-level constraints |

```ruby
class OrderService < Railsmith::BaseService
  model Order

  link_many :line_items, service: LineItemService, dependent: :destroy
end

# Destroy: runs LineItemService.call(action: :destroy) for each line item,
# then deletes the order — all inside one transaction.
OrderService.call(action: :destroy, params: { id: 42 }, context: ctx)
```

---

## Association-aware bulk operations

`bulk_create` accepts nested records per item when associations are declared. Two item formats are supported simultaneously:

```ruby
# Flat format — unchanged, still works exactly as before
items: [{ name: "A" }, { name: "B" }]

# Nested format — new
items: [
  {
    attributes: { total: 50.00 },
    line_items: [{ attributes: { product_id: 1, qty: 1 } }]
  },
  {
    attributes: { total: 75.00 },
    line_items: [
      { attributes: { product_id: 2, qty: 1 } },
      { attributes: { product_id: 3, qty: 2 } }
    ]
  }
]
```

The two formats are detected automatically by the presence of an `attributes:` key in each item hash.

---

## Inheritance

Association registries are deep-duped on inheritance. Subclasses can add or override associations without affecting the parent:

```ruby
class FullOrderService < OrderService
  link_many :discounts, service: DiscountService
end
```

---

## Generator support

Generate a service with association and eager loading declarations automatically:

```bash
# Introspects model associations
rails g railsmith:model_service Order --associations

# Both inputs and associations
rails g railsmith:model_service Order --inputs --associations
```

The generator reads `Model.reflect_on_all_associations` and emits `link_many`, `link_one`, and `link_ref` declarations plus an `includes` line. It adds `# TODO: Define XxxService` comments for associated service classes that don't exist yet.
