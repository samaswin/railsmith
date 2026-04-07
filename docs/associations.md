# Association Support

Railsmith v1.2.0 adds first-class association handling to services: eager loading, nested creates and updates, and cascading destroy — all within a single transaction.

---

## Association DSL

Declare associations at the class level using `has_many`, `has_one`, and `belongs_to`:

```ruby
class OrderService < Railsmith::BaseService
  model Order
  domain :commerce

  has_many   :line_items,       service: LineItemService, dependent: :destroy
  has_one    :shipping_address, service: AddressService,  dependent: :nullify
  belongs_to :customer,         service: CustomerService, optional: true
end
```

All three macros accept a `service:` option (required) pointing to the associated service class. Foreign keys are auto-inferred when not given.

### `has_many` / `has_one` options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `service:` | Class | required | service class for associated records |
| `foreign_key:` | Symbol | inferred | FK column on the child; defaults to `#{parent_model}_id` (e.g. `order_id`) |
| `dependent:` | Symbol | `:ignore` | cascade behaviour on parent destroy |
| `validate:` | Boolean | `true` | validate nested records before writing |

### `belongs_to` options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `service:` | Class | required | service class for the parent record |
| `foreign_key:` | Symbol | inferred | FK on this record; defaults to `#{association_name}_id` (e.g. `customer_id`) |
| `optional:` | Boolean | `false` | skip presence validation for the FK |

---

## Eager loading

The `includes` class macro declares eager loads applied automatically to `find` and `list`. Multiple calls are additive:

```ruby
class OrderService < Railsmith::BaseService
  model Order

  includes :line_items, :customer
  includes line_items: [:product, :variant]   # merged with the call above
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

**Transaction behavior:** all child writes run inside the parent's open transaction. Any failure (parent or child) rolls back the entire operation.

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

All nested operations run within the parent's transaction — any failure triggers a full rollback.

---

## Cascading destroy

When `has_many` or `has_one` is declared with a `dependent:` option, the `destroy` action handles associated records through their service before deleting the parent.

| `dependent:` | Behaviour |
|--------------|-----------|
| `:destroy` | calls child service `destroy` for each associated record |
| `:nullify` | calls child service `update` with FK set to `nil` |
| `:restrict` | returns `validation_error` failure if any children exist (parent is not deleted) |
| `:ignore` | does nothing — default, relies on DB-level constraints |

```ruby
class OrderService < Railsmith::BaseService
  model Order

  has_many :line_items,       service: LineItemService, dependent: :destroy
  has_one  :shipping_address, service: AddressService,  dependent: :nullify
end

# Destroy: runs LineItemService.call(action: :destroy) for each line item,
# then nullifies shipping_address.order_id, then deletes the order.
# All inside one transaction.
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
  has_many :discounts, service: DiscountService
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

The generator reads `Model.reflect_on_all_associations` and emits `has_many`, `has_one`, and `belongs_to` declarations plus an `includes` line. It adds `# TODO: Define XxxService` comments for associated service classes that don't exist yet.
