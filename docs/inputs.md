# Declarative Inputs & Type Coercion

The `input` DSL declares the parameters a service expects — their types, defaults, and constraints. When inputs are declared, Railsmith automatically coerces, validates, and filters params before the action runs.

---

## Basic declaration

```ruby
class UserService < Railsmith::BaseService
  model User
  domain :identity

  input :email,    String,   required: true
  input :age,      Integer,  default: nil
  input :role,     String,   in: %w[admin member guest], default: "member"
  input :active,   :boolean, default: true
  input :metadata, Hash,     default: -> { {} }
  input :tags,     Array,    default: []
end
```

Each `input` call registers one parameter definition on the service class.

---

## Options

| Option | Type | Description |
|--------|------|-------------|
| `required: true` | Boolean | Fail with `validation_error` if the key is absent or `nil` |
| `default:` | value or `-> { }` | Applied when the key is missing from params. Use a lambda for mutable defaults (`Hash`, `Array`) |
| `in:` | Array | Allowed values; anything else returns `validation_error` |
| `transform:` | `Proc` | Zero-arg proc applied after coercion (e.g. `transform: ->(v) { v.strip.downcase }`) |

---

## Type coercion

Railsmith converts incoming values to the declared type before validation. Coercion failures return a `validation_error` result immediately — the action never runs.

| Declared type | Coercion behaviour |
|---------------|-------------------|
| `String` | `value.to_s` |
| `Integer` | `Integer(value)` — strict; `"abc"` errors |
| `Float` | `Float(value)` — strict |
| `BigDecimal` | `BigDecimal(value.to_s)` |
| `:boolean` | `"true"/"1"/true → true`, `"false"/"0"/false → false`; other values error |
| `Date` | `Date.parse(value.to_s)` |
| `DateTime` | `DateTime.parse(value.to_s)` |
| `Time` | `Time.parse(value.to_s)` |
| `Symbol` | `value.to_sym` |
| `Array` | `Array(value)` — wraps scalars |
| `Hash` | passthrough; non-hash values error |

`nil` values skip coercion and are handled by the `required:` check instead.

---

## Where inputs apply

- **Model-backed services** (`model SomeClass` declared): inputs describe `params[:attributes]`.
- **Custom actions** (no `model`): inputs describe the top-level `params` hash.

---

## Input filtering

When any `input` is declared, only declared keys are forwarded to the action. Undeclared params are silently dropped. This prevents mass-assignment of unexpected fields.

To opt out:

```ruby
class LegacyService < Railsmith::BaseService
  filter_inputs false

  input :name, String
  # All other keys in params still reach the action
end
```

---

## Defaults

Static defaults are copied by value. Use a lambda for mutable values to avoid shared state:

```ruby
input :tags,     Array, default: []          # WRONG: shared array
input :tags,     Array, default: -> { [] }   # correct: fresh array per call
input :metadata, Hash,  default: -> { {} }   # correct
```

---

## `in:` constraints

```ruby
input :status, String, in: %w[draft published archived], default: "draft"
```

If a caller passes `status: "deleted"`, the service returns:

```ruby
Result.failure(error: Errors.validation_error(
  message: "Validation failed",
  details: { errors: { status: ["is not included in the list"] } }
))
```

---

## Custom transforms

```ruby
input :email, String, required: true, transform: ->(v) { v.strip.downcase }
input :slug,  String, transform: ->(v) { v.parameterize }
```

Transforms run after coercion and before the `in:` constraint check.

---

## Custom coercions

Register application-specific coercers globally:

```ruby
# config/initializers/railsmith.rb
Railsmith.configure do |c|
  c.register_coercion(:money, ->(v) { Money.new(v) })
end
```

Then use the custom type token in any service:

```ruby
input :price, :money, required: true
```

---

## Inheritance

Subclasses inherit all parent inputs and can add or override them independently:

```ruby
class BaseUserService < Railsmith::BaseService
  model User
  input :email, String, required: true
  input :role,  String, default: "member"
end

class AdminUserService < BaseUserService
  input :role, String, default: "admin"  # overrides parent default
  input :permissions, Array, default: -> { [] }
end
```

The parent's registry is unaffected by subclass additions.

---

## Interaction with `validate()`

The `input` DSL and `validate()` can coexist. Input resolution (coerce, validate, filter) runs first; then `validate()` runs on the resolved params. Both can return failures independently.

```ruby
class ProductService < Railsmith::BaseService
  model Product

  input :name,  String, required: true
  input :price, Float,  required: true

  def create
    val = validate(params, required_keys: [:category_id])  # additional check
    return val if val.failure?
    super
  end
end
```

> **Deprecation:** `required_keys:` on `validate()` is deprecated in v1.2.0. Migrate to `input :field, Type, required: true` instead.

---

## Generator support

Generate a service with input declarations automatically:

```bash
# Auto-introspect model columns
rails g railsmith:model_service User --inputs

# Explicit inputs
rails g railsmith:model_service User --inputs=email:string:required name:string age:integer
```

See [Generators](../README.md#generators) for full flag documentation.

---

## Error shape

All input failures return a standard `validation_error` result:

```ruby
result = UserService.call(action: :create, params: { attributes: { age: "not-a-number" } })
result.failure?          # => true
result.code              # => "validation_error"
result.error.details     # => { errors: { age: ["is not a valid Integer"], email: ["can't be blank"] } }
```
