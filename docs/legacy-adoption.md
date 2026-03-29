# Legacy Adoption Guide

How to incrementally introduce Railsmith into an existing Rails application without a big-bang rewrite.

---

## Principles

- **No forced migration.** Old code keeps working. Railsmith services live alongside existing code.
- **Strangler fig.** Wrap old logic inside services one model at a time, then delete the old paths.
- **Controller is the seam.** A controller action is the safest place to switch from inline model calls to a service call — the rest of the app stays unchanged.
- **Ship continuously.** Each phase produces a releasable diff. Never accumulate more than one phase of unreleased work.

---

## Phase 0 — Install without touching existing code

```bash
bundle add railsmith
rails generate railsmith:install
```

Commit only the initializer and empty directories. No behavior changes.

```ruby
# config/initializers/railsmith.rb
Railsmith.configure do |config|
  config.warn_on_cross_domain_calls = true
  config.strict_mode = false
  config.fail_on_arch_violations = false  # keep off until Phase 4
end
```

Verify nothing is broken:

```bash
bundle exec rspec
```

---

## Phase 1 — Audit what you have

Run the architecture checker in warn-only mode to see where models are accessed directly from controllers:

```bash
rake railsmith:arch_check
```

Save the output as a baseline. This list is your migration backlog. Prioritize by risk:
- High-write models (frequently mutated, complex validations) → migrate first.
- Read-only models → migrate last or skip.

---

## Phase 2 — Wrap one model at a time

Pick the simplest model from your backlog (few validations, no callbacks). Generate its service:

```bash
rails generate railsmith:model_service Post
```

Open `app/services/operations/post_service.rb`. For now, leave it as generated — the default CRUD actions are enough for the first replacement.

Find the controller that creates posts. Replace the inline model call:

**Before:**

```ruby
# app/controllers/posts_controller.rb
def create
  @post = Post.new(post_params)
  if @post.save
    redirect_to @post
  else
    render :new
  end
end
```

**After:**

```ruby
def create
  result = PostService.call(
    action: :create,
    params: { attributes: post_params.to_h }
  )

  if result.success?
    redirect_to result.value
  else
    @post = Post.new(post_params)  # re-build for form re-render
    @post.errors.merge!(ActiveModel::Errors.new(@post)) # optional: surface errors
    flash.now[:alert] = result.error.message
    render :new
  end
end
```

Test the controller thoroughly. Merge and deploy.

Repeat for `update` and `destroy` on the same model before moving to the next.

---

## Phase 3 — Move business logic into services

Once a controller is routing through a service, move inline business logic (currently in the controller or model callbacks) into the service as custom actions.

**Example — promoting to paid plan:**

Old controller:

```ruby
def upgrade
  @user = User.find(params[:id])
  @user.update!(plan: "paid", upgraded_at: Time.current)
  BillingMailer.upgraded(@user).deliver_later
  redirect_to @user
end
```

New service action:

```ruby
# app/services/operations/user_service.rb
module Operations
  class UserService < Railsmith::BaseService
    model(User)

    def upgrade
      id = params[:id]
      user = User.find_by(id: id)
      return Result.failure(error: Errors.not_found(details: { id: id })) unless user

      user.update!(plan: "paid", upgraded_at: Time.current)
      BillingMailer.upgraded(user).deliver_later
      Result.success(value: user)
    end
  end
end
```

Controller:

```ruby
def upgrade
  result = UserService.call(
    action: :upgrade,
    params: { id: params[:id] }
  )
  result.success? ? redirect_to result.value : redirect_back(fallback_location: root_path)
end
```

---

## Phase 4 — Introduce domain boundaries (optional)

Once several related models are wrapped, group them into a domain.

```bash
rails generate railsmith:domain Billing
rails generate railsmith:model_service Billing::Invoice --domain=Billing
rails generate railsmith:model_service Billing::Payment --domain=Billing
```

Move the service files from `app/services/operations/` to `app/domains/billing/services/` and add `domain`:

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

Update all callers to use the new namespace. The `warn_on_cross_domain_calls` flag will surface any places that call billing services from non-billing contexts, without breaking them.

---

## Phase 5 — Enable architecture enforcement in CI

Once the migration is sufficiently complete, turn on the arch check in CI:

```ruby
# config/initializers/railsmith.rb
Railsmith.configure do |config|
  config.fail_on_arch_violations = true
end
```

Or via environment variable in CI only:

```yaml
# .github/workflows/ci.yml
- name: Architecture check
  run: RAILSMITH_FAIL_ON_ARCH_VIOLATIONS=true bundle exec rake railsmith:arch_check
```

This prevents new direct model access from being introduced into controllers.

---

## Migration checklist

Use this checklist per model:

- [ ] Generated service with `rails g railsmith:model_service`
- [ ] Controller `create` replaced with service call
- [ ] Controller `update` replaced with service call
- [ ] Controller `destroy` replaced with service call
- [ ] Custom controller actions moved to named service methods
- [ ] Old model callbacks reviewed — move to service if business logic
- [ ] Tests updated: service spec added, controller spec uses service double or real service
- [ ] `rake railsmith:arch_check` shows no violations for this model

---

## Testing strategy during migration

**For controllers under migration**, prefer integration tests that call the real service rather than stubbing it. This catches regressions where the controller and service disagree on the interface.

**For services**, write isolated unit specs:

```ruby
# spec/services/post_service_spec.rb
RSpec.describe PostService do
  describe "#create" do
    it "creates a post" do
      result = described_class.call(
        action: :create,
        params: { attributes: { title: "Hello", body: "World" } }
      )
      expect(result).to be_success
      expect(result.value).to be_a(Post)
      expect(result.value.title).to eq("Hello")
    end

    it "returns validation_error when title is blank" do
      result = described_class.call(
        action: :create,
        params: { attributes: { title: "", body: "World" } }
      )
      expect(result).to be_failure
      expect(result.code).to eq("validation_error")
    end
  end
end
```

---

## Common pitfalls

**Returning the AR error object in failure results.**
The default CRUD actions handle this automatically. In custom actions, build the error explicitly:

```ruby
# Correct
return Result.failure(error: Errors.validation_error(
  message: record.errors.full_messages.to_sentence,
  details: { errors: record.errors.to_h }
))
```

**Forgetting to forward `context:`.**
When a service calls another service, always pass `context: context` so domain tracking propagates.

**Wrapping service calls in rescue.**
Don't. Services return `Result.failure` for all expected error conditions. Rescuing exceptions at the caller layer bypasses error mapping and loses structure.

**Moving too much at once.**
One model, one PR. Smaller diffs are easier to review and easier to revert.
