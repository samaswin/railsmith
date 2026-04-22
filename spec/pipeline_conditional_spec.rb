# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Pipeline conditional steps" do
  def make_service(action, result_proc)
    Class.new(Railsmith::BaseService) do
      define_method(action) { instance_exec(&result_proc) }
    end
  end

  def success_service(action, value: nil)
    make_service(action, -> { Railsmith::Result.success(value: value) })
  end

  def failure_service(action, code: :unexpected, message: "step failed")
    make_service(action, -> { Railsmith::Result.failure(code: code, message: message) })
  end

  def build_pipeline(&block)
    Class.new(Railsmith::Pipeline, &block)
  end

  after { Railsmith::Instrumentation.reset! }

  # ---------------------------------------------------------------------------
  # StepDefinition#skip?
  # ---------------------------------------------------------------------------

  describe "StepDefinition#skip?" do
    let(:svc) { success_service(:go) }

    def defn(condition: nil, polarity: :if, **rest)
      Railsmith::Pipeline::StepDefinition.new(
        name: :s, service: svc, action: :go, inputs: nil, rollback: nil,
        on_failure_continue: false,
        condition: condition, polarity: polarity, **rest
      )
    end

    it "returns false when no condition is set" do
      expect(defn.skip?({}, nil)).to be false
    end

    it "returns false (do not skip) when if: proc returns true" do
      d = defn(condition: ->(_p, _c) { true }, polarity: :if)
      expect(d.skip?({}, nil)).to be false
    end

    it "returns true (skip) when if: proc returns false" do
      d = defn(condition: ->(_p, _c) { false }, polarity: :if)
      expect(d.skip?({}, nil)).to be true
    end

    it "returns false (do not skip) when unless: proc returns false" do
      d = defn(condition: ->(_p, _c) { false }, polarity: :unless)
      expect(d.skip?({}, nil)).to be false
    end

    it "returns true (skip) when unless: proc returns true" do
      d = defn(condition: ->(_p, _c) { true }, polarity: :unless)
      expect(d.skip?({}, nil)).to be true
    end

    it "passes accumulated_params to the proc" do
      received = nil
      d = defn(condition: lambda { |p, _c|
        received = p
        true
      }, polarity: :if)
      d.skip?({ foo: 1 }, nil)
      expect(received).to eq({ foo: 1 })
    end

    it "passes context to the proc" do
      received = nil
      ctx = Railsmith::Context.build({ actor_id: 5 })
      d = defn(condition: lambda { |_p, c|
        received = c
        true
      }, polarity: :if)
      d.skip?({}, ctx)
      expect(received[:actor_id]).to eq(5)
    end

    it "raises GuardNotFoundError for an unknown symbol condition" do
      d = defn(condition: :missing_guard, polarity: :if)
      expect { d.skip?({}, nil, {}) }
        .to raise_error(Railsmith::Pipeline::GuardNotFoundError, /:missing_guard/)
    end

    it "resolves a symbol condition from the guards hash" do
      guard_proc = ->(_p, _c) { true }
      d = defn(condition: :my_guard, polarity: :if)
      expect(d.skip?({}, nil, { my_guard: guard_proc })).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # Pipeline.step — if:/unless: DSL
  # ---------------------------------------------------------------------------

  describe ".step with if:/unless:" do
    it "stores a proc condition with :if polarity" do
      svc = success_service(:go)
      cond = ->(_p, _c) { true }
      pipeline = build_pipeline { step :s, service: svc, action: :go, if: cond }

      defn = pipeline.step_definitions.first
      expect(defn.condition).to be(cond)
      expect(defn.polarity).to  eq(:if)
    end

    it "stores a proc condition with :unless polarity" do
      svc = success_service(:go)
      cond = ->(_p, _c) { false }
      pipeline = build_pipeline { step :s, service: svc, action: :go, unless: cond }

      defn = pipeline.step_definitions.first
      expect(defn.condition).to be(cond)
      expect(defn.polarity).to  eq(:unless)
    end

    it "stores a symbol condition referencing a named guard" do
      svc = success_service(:go)
      pipeline = build_pipeline { step :s, service: svc, action: :go, if: :my_guard }

      defn = pipeline.step_definitions.first
      expect(defn.condition).to eq(:my_guard)
      expect(defn.polarity).to  eq(:if)
    end

    it "defaults condition to nil when if:/unless: are omitted" do
      svc = success_service(:go)
      pipeline = build_pipeline { step :s, service: svc, action: :go }

      defn = pipeline.step_definitions.first
      expect(defn.condition).to be_nil
    end

    it "raises ArgumentError when both if: and unless: are given" do
      svc = success_service(:go)
      expect do
        build_pipeline { step :s, service: svc, action: :go, if: ->(_p, _c) {}, unless: ->(_p, _c) {} }
      end.to raise_error(ArgumentError, /if.*unless/)
    end
  end

  # ---------------------------------------------------------------------------
  # Pipeline.guard helper
  # ---------------------------------------------------------------------------

  describe ".guard" do
    it "registers a named guard predicate" do
      pipeline = build_pipeline { guard(:has_coupon?) { |params, _ctx| params.key?(:coupon_code) } }
      expect(pipeline.guards).to have_key(:has_coupon?)
      expect(pipeline.guards[:has_coupon?]).to be_a(Proc)
    end

    it "raises ArgumentError when called without a block" do
      expect { build_pipeline { guard(:no_block) } }.to raise_error(ArgumentError, /block/)
    end

    it "inherits guards from parent pipeline" do
      parent = build_pipeline { guard(:from_parent) { |_p, _c| true } }
      child  = Class.new(parent)
      expect(child.guards).to have_key(:from_parent)
    end

    it "child guard additions do not leak to parent" do
      parent = build_pipeline {} # rubocop:disable Lint/EmptyBlock
      child  = Class.new(parent)
      child.guard(:child_only) { |_p, _c| true }
      expect(parent.guards).not_to have_key(:child_only)
    end
  end

  # ---------------------------------------------------------------------------
  # Conditional execution via if:
  # ---------------------------------------------------------------------------

  describe "if: proc condition" do
    it "executes the step when the proc returns true" do
      called = false
      svc = Class.new(Railsmith::BaseService) do
        define_method(:go) do
          called = true
          Railsmith::Result.success
        end
      end

      build_pipeline do
        step :s, service: svc, action: :go, if: ->(_p, _c) { true }
      end.call(params: {})

      expect(called).to be true
    end

    it "skips the step when the proc returns false" do
      called = false
      svc = Class.new(Railsmith::BaseService) do
        define_method(:go) do
          called = true
          Railsmith::Result.success
        end
      end

      build_pipeline do
        step :s, service: svc, action: :go, if: ->(_p, _c) { false }
      end.call(params: {})

      expect(called).to be false
    end

    it "evaluates the proc with the current accumulated params" do
      svc_a = success_service(:go, value: { feature_on: true })
      called = false
      svc_b = Class.new(Railsmith::BaseService) do
        define_method(:go) do
          called = true
          Railsmith::Result.success
        end
      end

      build_pipeline do
        step :first,  service: svc_a, action: :go
        step :second, service: svc_b, action: :go, if: ->(params, _c) { params[:feature_on] }
      end.call(params: {})

      expect(called).to be true
    end

    it "pipeline still succeeds when a conditional step is skipped" do
      svc = success_service(:go)
      skip_svc = failure_service(:go) # would fail if executed

      result = build_pipeline do
        step :ok,  service: svc,      action: :go
        step :bad, service: skip_svc, action: :go, if: ->(_p, _c) { false }
      end.call(params: {})

      expect(result).to be_success
    end
  end

  # ---------------------------------------------------------------------------
  # Conditional execution via unless:
  # ---------------------------------------------------------------------------

  describe "unless: proc condition" do
    it "executes the step when the proc returns false" do
      called = false
      svc = Class.new(Railsmith::BaseService) do
        define_method(:go) do
          called = true
          Railsmith::Result.success
        end
      end

      build_pipeline do
        step :s, service: svc, action: :go, unless: ->(_p, _c) { false }
      end.call(params: {})

      expect(called).to be true
    end

    it "skips the step when the proc returns true" do
      called = false
      svc = Class.new(Railsmith::BaseService) do
        define_method(:go) do
          called = true
          Railsmith::Result.success
        end
      end

      build_pipeline do
        step :s, service: svc, action: :go, unless: ->(_p, _c) { true }
      end.call(params: {})

      expect(called).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # Named guard with symbol condition
  # ---------------------------------------------------------------------------

  describe "if: :named_guard" do
    it "executes the step when the guard returns true" do
      called = false
      svc = Class.new(Railsmith::BaseService) do
        define_method(:go) do
          called = true
          Railsmith::Result.success
        end
      end

      build_pipeline do
        guard(:always) { |_p, _c| true }
        step :s, service: svc, action: :go, if: :always
      end.call(params: {})

      expect(called).to be true
    end

    it "skips the step when the guard returns false" do
      called = false
      svc = Class.new(Railsmith::BaseService) do
        define_method(:go) do
          called = true
          Railsmith::Result.success
        end
      end

      build_pipeline do
        guard(:never) { |_p, _c| false }
        step :s, service: svc, action: :go, if: :never
      end.call(params: {})

      expect(called).to be false
    end

    it "raises GuardNotFoundError at runtime when the guard name is unknown" do
      svc = success_service(:go)
      pipeline = build_pipeline { step :s, service: svc, action: :go, if: :no_such_guard }

      expect { pipeline.call(params: {}) }
        .to raise_error(Railsmith::Pipeline::GuardNotFoundError, /:no_such_guard/)
    end
  end

  # ---------------------------------------------------------------------------
  # Skipped steps emit pipeline.step.skipped.railsmith
  # ---------------------------------------------------------------------------

  describe "pipeline.step.skipped.railsmith event" do
    it "emits the event when a step is skipped" do
      events = []
      Railsmith::Instrumentation.subscribe("pipeline.step.skipped.railsmith") { |_, p| events << p }

      svc = success_service(:go)
      build_pipeline do
        step :skipped_step, service: svc, action: :go, if: ->(_p, _c) { false }
      end.call(params: {})

      expect(events.size).to eq(1)
      expect(events.first[:step]).to eq(:skipped_step)
    end

    it "includes :pipeline in the skipped event payload" do
      stub_const("ConditionalPipeline", Class.new(Railsmith::Pipeline) do
        step :s, service: Class.new(Railsmith::BaseService) {
          def go = Railsmith::Result.success
        }, action: :go, if: ->(_p, _c) { false }
      end)

      events = []
      Railsmith::Instrumentation.subscribe("pipeline.step.skipped.railsmith") { |_, p| events << p }

      ConditionalPipeline.call(params: {})
      expect(events.first[:pipeline]).to eq("ConditionalPipeline")
    end

    it "does not emit the skipped event for steps that run normally" do
      events = []
      Railsmith::Instrumentation.subscribe("pipeline.step.skipped.railsmith") { |_, p| events << p }

      svc = success_service(:go)
      build_pipeline { step :s, service: svc, action: :go }.call(params: {})

      expect(events).to be_empty
    end

    it "emits one skipped event per skipped step" do
      events = []
      Railsmith::Instrumentation.subscribe("pipeline.step.skipped.railsmith") { |_, p| events << p }

      svc = success_service(:go)
      build_pipeline do
        step :a, service: svc, action: :go, if: ->(_p, _c) { false }
        step :b, service: svc, action: :go
        step :c, service: svc, action: :go, unless: ->(_p, _c) { true }
      end.call(params: {})

      expect(events.map { |e| e[:step] }).to eq(%i[a c])
    end
  end

  # ---------------------------------------------------------------------------
  # Skipped steps are not rolled back
  # ---------------------------------------------------------------------------

  describe "skipped steps are not rolled back" do
    it "does not invoke rollback on a skipped step when a later step fails" do
      rollback_called = false

      svc_with_rollback = Class.new(Railsmith::BaseService) do
        define_method(:go)   { Railsmith::Result.success }
        define_method(:undo) do
          rollback_called = true
          Railsmith::Result.success
        end
      end
      fail_svc = failure_service(:go)

      build_pipeline do
        # This step is skipped — its rollback must never fire
        step :skipped, service: svc_with_rollback, action: :go,
                       rollback: :undo, if: ->(_p, _c) { false }
        step :fails, service: fail_svc, action: :go
      end.call(params: {})

      expect(rollback_called).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # on_failure_continue
  # ---------------------------------------------------------------------------

  describe "on_failure_continue:" do
    it "defaults to false when omitted" do
      svc = success_service(:go)
      pipeline = build_pipeline { step :s, service: svc, action: :go }
      expect(pipeline.step_definitions.first.continue_on_failure?).to be false
    end

    it "continues past a failing step when true" do
      calls = []
      fail_svc = Class.new(Railsmith::BaseService) do
        define_method(:go) do
          calls << :fail_step
          Railsmith::Result.failure(message: "non-critical error")
        end
      end
      ok_svc = Class.new(Railsmith::BaseService) do
        define_method(:go) do
          calls << :ok_step
          Railsmith::Result.success
        end
      end

      result = build_pipeline do
        step :non_critical, service: fail_svc, action: :go, on_failure_continue: true
        step :critical,     service: ok_svc,   action: :go
      end.call(params: {})

      expect(calls).to eq(%i[fail_step ok_step])
      expect(result).to be_success
    end

    it "pipeline returns success when only on_failure_continue steps fail" do
      fail_svc = failure_service(:go, message: "optional step failed")
      result = build_pipeline do
        step :opt, service: fail_svc, action: :go, on_failure_continue: true
      end.call(params: {})

      expect(result).to be_success
    end

    it "does not roll back a failed on_failure_continue step on later failure" do
      rollback_called = false

      non_critical = Class.new(Railsmith::BaseService) do
        def go = Railsmith::Result.failure(message: "non-critical")
        define_method(:undo) do
          rollback_called = true
          Railsmith::Result.success
        end
      end
      fail_svc = failure_service(:go)

      build_pipeline do
        step :non_critical, service: non_critical, action: :go,
                            rollback: :undo, on_failure_continue: true
        step :later_fail,   service: fail_svc,     action: :go
      end.call(params: {})

      expect(rollback_called).to be false
    end

    it "halts and rolls back normal steps even when on_failure_continue step precedes them" do
      rolled_back = []

      normal_svc    = Class.new(Railsmith::BaseService) do
        def go = Railsmith::Result.success
        define_method(:undo) do
          rolled_back << :normal
          Railsmith::Result.success
        end
      end
      fail_svc      = failure_service(:go)
      non_crit_svc  = failure_service(:go)

      result = build_pipeline do
        step :non_critical, service: non_crit_svc, action: :go, on_failure_continue: true
        step :normal,       service: normal_svc,   action: :go, rollback: :undo
        step :hard_fail,    service: fail_svc, action: :go
      end.call(params: {})

      expect(result).to be_failure
      expect(rolled_back).to eq([:normal])
    end
  end
end
