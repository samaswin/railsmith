# frozen_string_literal: true

require "spec_helper"

# Unit-level coverage for the lifecycle hook DSL. Integration-level coverage
# (audit logging, event publishing, global hooks) lives in
# spec/hooks_integration_spec.rb to keep each file focused.
RSpec.describe Railsmith::Hooks do
  # Shared hook-friendly service factory. Each example builds a fresh anonymous
  # class so registry state never leaks between tests.
  def service_class(&body)
    Class.new(Railsmith::BaseService, &body)
  end

  after { Railsmith.configuration.reset_global_hooks! }

  describe "before hooks" do
    it "runs before hooks in declaration order before the action" do
      events = []
      klass = service_class do
        before :create do
          events << :first
        end

        before :create do
          events << :second
        end

        define_method(:create) do
          events << :action
          Railsmith::Result.success(value: :ok)
        end
      end

      klass.call(action: :create, params: {}, context: {})

      expect(events).to eq(%i[first second action])
    end

    it "evaluates before blocks in the service instance context" do
      captured = nil
      klass = service_class do
        before :create do
          captured = context[:actor_id]
        end

        define_method(:create) do
          Railsmith::Result.success(value: :ok)
        end
      end

      klass.call(action: :create, params: {}, context: { actor_id: 42 })

      expect(captured).to eq(42)
    end

    it "applies a before hook to multiple actions declared in one call" do
      seen = []
      klass = service_class do
        before :create, :update do
          seen << :hit
        end

        define_method(:create) { Railsmith::Result.success(value: :c) }
        define_method(:update) { Railsmith::Result.success(value: :u) }
      end

      klass.call(action: :create, params: {}, context: {})
      klass.call(action: :update, params: {}, context: {})

      expect(seen).to eq(%i[hit hit])
    end

    it "does not fire a before hook for unrelated actions" do
      counter = 0
      klass = service_class do
        before :create do
          counter += 1
        end

        define_method(:create) { Railsmith::Result.success(value: :ok) }
        define_method(:update) { Railsmith::Result.success(value: :ok) }
      end

      klass.call(action: :update, params: {}, context: {})
      expect(counter).to eq(0)
    end
  end

  describe "after hooks" do
    it "receives the Result as the block argument" do
      observed = nil
      klass = service_class do
        after :create do |result|
          observed = result
        end

        define_method(:create) do
          Railsmith::Result.success(value: { id: 1 })
        end
      end

      final = klass.call(action: :create, params: {}, context: {})

      expect(observed).to be(final)
      expect(observed.value).to eq({ id: 1 })
    end

    it "still fires when the action returns a failure Result" do
      observed_success = nil
      klass = service_class do
        after :create do |result|
          observed_success = result.success?
        end

        define_method(:create) do
          Railsmith::Result.failure(message: "nope")
        end
      end

      klass.call(action: :create, params: {}, context: {})

      expect(observed_success).to be(false)
    end

    it "cannot rewrite the result returned to the caller" do
      klass = service_class do
        after :create do |_result|
          # Even if an after hook evaluates to a different value,
          # BaseService already decided the return value.
          Railsmith::Result.success(value: :different)
        end

        define_method(:create) do
          Railsmith::Result.success(value: :original)
        end
      end

      final = klass.call(action: :create, params: {}, context: {})
      expect(final.value).to eq(:original)
    end
  end

  describe "around hooks" do
    it "wraps the action and the block return value becomes the Result" do
      klass = service_class do
        around :create do |action|
          original = action.call
          Railsmith::Result.success(value: { wrapped: original.value })
        end

        define_method(:create) do
          Railsmith::Result.success(value: :inner)
        end
      end

      result = klass.call(action: :create, params: {}, context: {})
      expect(result.value).to eq({ wrapped: :inner })
    end

    it "nests multiple around hooks (outer declared first wraps inner)" do
      trace = []
      klass = service_class do
        around :create do |action|
          trace << :outer_in
          result = action.call
          trace << :outer_out
          result
        end

        around :create do |action|
          trace << :inner_in
          result = action.call
          trace << :inner_out
          result
        end

        define_method(:create) do
          trace << :action
          Railsmith::Result.success(value: :ok)
        end
      end

      klass.call(action: :create, params: {}, context: {})

      expect(trace).to eq(%i[outer_in inner_in action inner_out outer_out])
    end

    it "raises AroundHookNotYieldedError when the block forgets to call action" do
      klass = service_class do
        around :create, name: :forgetful do |_action|
          Railsmith::Result.success(value: :swallowed)
        end

        define_method(:create) do
          Railsmith::Result.success(value: :never_seen)
        end
      end

      expect do
        klass.call(action: :create, params: {}, context: {})
      end.to raise_error(Railsmith::Hooks::AroundHookNotYieldedError, /forgetful/)
    end
  end

  describe "execution sandwich" do
    it "runs before → around → action → after in that order" do
      order = []
      klass = service_class do
        before :create do
          order << :before
        end

        around :create do |action|
          order << :around_in
          result = action.call
          order << :around_out
          result
        end

        after :create do |_result|
          order << :after
        end

        define_method(:create) do
          order << :action
          Railsmith::Result.success(value: :ok)
        end
      end

      klass.call(action: :create, params: {}, context: {})

      expect(order).to eq(%i[before around_in action around_out after])
    end
  end

  describe "conditional hooks" do
    it "runs an if: hook only when the symbol predicate returns truthy" do
      hits = []
      klass = service_class do
        before :create, if: :admin? do
          hits << :fired
        end

        define_method(:create) { Railsmith::Result.success(value: :ok) }
        define_method(:admin?) { context[:actor_role] == :admin }
      end

      klass.call(action: :create, params: {}, context: { actor_role: :member })
      expect(hits).to be_empty

      klass.call(action: :create, params: {}, context: { actor_role: :admin })
      expect(hits).to eq([:fired])
    end

    it "runs an unless: hook only when the predicate is falsy" do
      hits = []
      klass = service_class do
        before :update, unless: ->(svc) { svc.params[:draft] } do
          hits << :fired
        end

        define_method(:update) { Railsmith::Result.success(value: :ok) }
      end

      klass.call(action: :update, params: { draft: true }, context: {})
      expect(hits).to be_empty

      klass.call(action: :update, params: { draft: false }, context: {})
      expect(hits).to eq([:fired])
    end

    it "rejects declaring both if: and unless: on the same hook" do
      expect do
        service_class do
          before(:create, if: :x?, unless: :y?) { :noop }
        end
      end.to raise_error(ArgumentError, /both if: and unless:/)
    end
  end

  describe "inheritance" do
    it "subclasses inherit parent hooks and run them before their own" do
      events = []
      parent = service_class do
        before :create do
          events << :parent
        end

        define_method(:create) { Railsmith::Result.success(value: :ok) }
      end

      child = Class.new(parent) do
        before :create do
          events << :child
        end
      end

      child.call(action: :create, params: {}, context: {})

      expect(events).to eq(%i[parent child])
    end

    it "declaring a hook on a subclass does not leak back to the parent" do
      parent = service_class do
        define_method(:create) { Railsmith::Result.success(value: :ok) }
      end

      child = Class.new(parent) do
        before :create do
          :child_only
        end
      end

      expect(parent.hooks_for(:create).size).to eq(0)
      expect(child.hooks_for(:create).size).to eq(1)
    end

    it "skip_before removes an inherited named hook from the subclass only" do
      events = []
      parent = service_class do
        before :create, name: :audit_log do
          events << :audit
        end

        define_method(:create) { Railsmith::Result.success(value: :ok) }
      end

      child = Class.new(parent) do
        skip_before :create, :audit_log
      end

      child.call(action: :create, params: {}, context: {})
      expect(events).to be_empty

      parent.call(action: :create, params: {}, context: {})
      expect(events).to eq([:audit])
    end

    it "skip_hook removes a named hook regardless of type" do
      events = []
      parent = service_class do
        before :create, name: :audit do
          events << :before
        end
        after :create, name: :audit do |_|
          events << :after
        end

        define_method(:create) { Railsmith::Result.success(value: :ok) }
      end

      child = Class.new(parent) do
        skip_hook :audit
      end

      child.call(action: :create, params: {}, context: {})
      expect(events).to be_empty
    end
  end

  describe "hooks_for introspection" do
    it "returns a HookChain including inherited entries in declaration order" do
      parent = service_class do
        before :create, name: :auth do
          :parent
        end
      end

      child = Class.new(parent) do
        before :create, name: :rate_limit do
          :child
        end
      end

      chain = child.hooks_for(:create)
      expect(chain.size).to eq(2)
      expect(chain.entries.map(&:name)).to eq(%i[auth rate_limit])
    end
  end

  describe "no hooks declared" do
    it "leaves existing BaseService behavior untouched" do
      klass = service_class do
        define_method(:create) do
          Railsmith::Result.success(value: :plain)
        end
      end

      result = klass.call(action: :create, params: {}, context: {})
      expect(result).to be_success
      expect(result.value).to eq(:plain)
    end
  end
end
