# `call!` — Raising Variant

`BaseService.call!` is identical to `call` but raises `Railsmith::Failure` instead of returning a failure result. It is designed for controller contexts where `rescue_from` is preferred over conditional branching.

---

## Usage

```ruby
# Returns Result on success; raises Railsmith::Failure on any failure
result = UserService.call!(
  action: :create,
  params: { attributes: { email: "alice@example.com" } },
  context: ctx
)

result.value  # => <User>
```

---

## `Railsmith::Failure`

`Railsmith::Failure` is a `StandardError` subclass that wraps the failure `Result`. It carries the full structured error payload so rescue handlers can inspect it without parsing a string.

```ruby
rescue Railsmith::Failure => e
  e.result   # => Railsmith::Result (failure)
  e.code     # => "validation_error"
  e.error    # => Railsmith::Errors::ErrorPayload
  e.meta     # => { request_id: "..." }
  e.message  # => "Validation failed" (from the error payload)
end
```

---

## Controller integration with `ControllerHelpers`

Include `Railsmith::ControllerHelpers` in `ApplicationController` to get automatic JSON error responses for all `Railsmith::Failure` exceptions:

```ruby
class ApplicationController < ActionController::API
  include Railsmith::ControllerHelpers
end
```

Any `call!` failure anywhere in the request will be caught and rendered as JSON with the correct HTTP status:

| Error code | HTTP status |
|------------|-------------|
| `validation_error` | 422 Unprocessable Entity |
| `not_found` | 404 Not Found |
| `conflict` | 409 Conflict |
| `unauthorized` | 401 Unauthorized |
| `unexpected` | 500 Internal Server Error |
| _(unknown)_ | 500 Internal Server Error |

The rendered JSON body is `result.to_h` — the same shape as every other Railsmith failure response:

```json
{
  "success": false,
  "value": null,
  "error": {
    "code": "validation_error",
    "message": "Validation failed",
    "details": { "errors": { "email": ["is invalid"] } }
  },
  "meta": { "request_id": "550e8400-e29b-41d4-a716-446655440000" }
}
```

---

## Controller without `ControllerHelpers`

You can also rescue `Railsmith::Failure` manually for custom handling:

```ruby
class UsersController < ApplicationController
  def create
    result = UserService.call!(
      action: :create,
      params: { attributes: user_params },
      context: ctx
    )
    render json: result.value, status: :created
  rescue Railsmith::Failure => e
    render json: e.result.to_h, status: :unprocessable_entity
  end
end
```

---

## Choosing between `call` and `call!`

| Use `call` when... | Use `call!` when... |
|--------------------|---------------------|
| You want to inspect the result and branch | You use `rescue_from` in the controller |
| Failures are expected and need custom handling | Failures are exceptional and handled globally |
| You're inside a service calling another service | You're at the controller boundary |
| You need to differentiate between error codes | A single error handler covers all failure types |

---

## Calling `call!` inside another service

Use `call!` within a service when you want a nested failure to bubble up and abort the outer operation immediately:

```ruby
class CheckoutService < Railsmith::BaseService
  def process
    # If InventoryService fails, Failure is raised and propagates up
    stock = InventoryService.call!(action: :reserve, params: { sku: params[:sku] }, context: context)

    OrderService.call!(action: :create, params: { attributes: { sku: params[:sku] } }, context: context)
  rescue Railsmith::Failure => e
    e.result  # return the structured failure from whichever nested call failed
  end
end
```
