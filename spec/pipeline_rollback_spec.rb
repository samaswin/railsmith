# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Pipeline rollback & compensation" do
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
  # StepDefinition — rollback field
  # ---------------------------------------------------------------------------

  describe "StepDefinition#has_rollback?" do
    it "returns false when no rollback is declared" do
      defn = Railsmith::Pipeline::StepDefinition.new(
        name: :s, service: success_service(:go), action: :go, inputs: nil, rollback: nil
      )
      expect(defn.has_rollback?).to be false
    end

    it "returns true for a symbol rollback" do
      defn = Railsmith::Pipeline::StepDefinition.new(
        name: :s, service: success_service(:go), action: :go, inputs: nil, rollback: :undo
      )
      expect(defn.has_rollback?).to be true
    end

    it "returns true for a proc rollback" do
      defn = Railsmith::Pipeline::StepDefinition.new(
        name: :s, service: success_service(:go), action: :go, inputs: nil, rollback: -> (_r, _c) {}
      )
      expect(defn.has_rollback?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # Pipeline.step DSL — rollback: option
  # ---------------------------------------------------------------------------

  describe ".step with rollback:" do
    it "stores a symbol rollback on the StepDefinition" do
      svc = success_service(:go)
      pipeline = build_pipeline { step :s, service: svc, action: :go, rollback: :undo }
      expect(pipeline.step_definitions.first.rollback).to eq(:undo)
    end

    it "stores a proc rollback on the StepDefinition" do
      svc      = success_service(:go)
      handler  = ->(r, c) {}
      pipeline = build_pipeline { step :s, service: svc, action: :go, rollback: handler }
      expect(pipeline.step_definitions.first.rollback).to be(handler)
    end

    it "defaults rollback to nil when omitted" do
      svc = success_service(:go)
      pipeline = build_pipeline { step :s, service: svc, action: :go }
      expect(pipeline.step_definitions.first.rollback).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Rollback execution order
  # ---------------------------------------------------------------------------

  describe "rollback execution on failure" do
    it "calls rollbacks in reverse step order" do
      rolled_back = []

      make_rollback_service = lambda do |label, rollback_action|
        Class.new(Railsmith::BaseService) do
          define_method(:go)          { Railsmith::Result.success(value: { "#{label}_id": 1 }) }
          define_method(rollback_action) do
            rolled_back << label
            Railsmith::Result.success
          end
        end
      end

      svc_a    = make_rollback_service.call(:a, :undo_a)
      svc_b    = make_rollback_service.call(:b, :undo_b)
      fail_svc = failure_service(:go)

      build_pipeline do
        step :step_a, service: svc_a,    action: :go, rollback: :undo_a
        step :step_b, service: svc_b,    action: :go, rollback: :undo_b
        step :step_c, service: fail_svc, action: :go
      end.call(params: {})

      expect(rolled_back).to eq([:b, :a])
    end

    it "does not call rollback on the failing step" do
      rolled_back = []

      fail_svc = Class.new(Railsmith::BaseService) do
        def go = Railsmith::Result.failure(message: "boom")
        define_method(:undo) do
          rolled_back << :fail_step
          Railsmith::Result.success
        end
      end

      build_pipeline do
        step :bad, service: fail_svc, action: :go, rollback: :undo
      end.call(params: {})

      expect(rolled_back).to be_empty
    end

    it "does not call rollback on steps that were never executed" do
      rolled_back = []

      fail_svc   = failure_service(:go)
      unrun_svc  = Class.new(Railsmith::BaseService) do
        define_method(:go)   { Railsmith::Result.success }
        define_method(:undo) do
          rolled_back << :unrun
          Railsmith::Result.success
        end
      end

      build_pipeline do
        step :fails,  service: fail_svc,  action: :go
        step :unrun,  service: unrun_svc, action: :go, rollback: :undo
      end.call(params: {})

      expect(rolled_back).to be_empty
    end

    it "skips steps that completed successfully but have no rollback declared" do
      rolled_back = []

      svc_with    = Class.new(Railsmith::BaseService) do
        def go = Railsmith::Result.success
        define_method(:undo) do
          rolled_back << :has_rollback
          Railsmith::Result.success
        end
      end
      svc_without = success_service(:go)
      fail_svc    = failure_service(:go)

      build_pipeline do
        step :has_rollback, service: svc_with,    action: :go, rollback: :undo
        step :no_rollback,  service: svc_without, action: :go
        step :fails,        service: fail_svc,    action: :go
      end.call(params: {})

      expect(rolled_back).to eq([:has_rollback])
    end

    it "still succeeds when no steps have rollback declared" do
      fail_svc = failure_service(:go)
      svc      = success_service(:go)

      pipeline = build_pipeline do
        step :s1, service: svc,      action: :go
        step :s2, service: fail_svc, action: :go
      end

      expect { pipeline.call(params: {}) }.not_to raise_error
    end
  end

  # ---------------------------------------------------------------------------
  # Rollback handler invocation — Symbol
  # ---------------------------------------------------------------------------

  describe "symbol rollback" do
    it "calls the named action on the same service class" do
      rollback_called = false

      svc = Class.new(Railsmith::BaseService) do
        def go  = Railsmith::Result.success(value: { item_id: 99 })
        define_method(:undo) do
          rollback_called = true
          Railsmith::Result.success
        end
      end
      fail_svc = failure_service(:go)

      build_pipeline do
        step :s1, service: svc,      action: :go,  rollback: :undo
        step :s2, service: fail_svc, action: :go
      end.call(params: {})

      expect(rollback_called).to be true
    end

    it "passes the forward step's params merged with its result.value as rollback params" do
      received_params = nil

      svc = Class.new(Railsmith::BaseService) do
        def go = Railsmith::Result.success(value: { reservation_id: "rsv-1" })
        define_method(:undo) do
          received_params = params
          Railsmith::Result.success
        end
      end
      fail_svc = failure_service(:go)

      build_pipeline do
        step :reserve, service: svc,      action: :go,  rollback: :undo
        step :pay,     service: fail_svc, action: :go
      end.call(params: { cart_id: 42 })

      expect(received_params).to include(cart_id: 42, reservation_id: "rsv-1")
    end

    it "passes the pipeline context to the rollback service" do
      received_context = nil

      svc = Class.new(Railsmith::BaseService) do
        def go = Railsmith::Result.success
        define_method(:undo) do
          received_context = context
          Railsmith::Result.success
        end
      end
      fail_svc = failure_service(:go)

      build_pipeline do
        step :s1, service: svc,      action: :go, rollback: :undo
        step :s2, service: fail_svc, action: :go
      end.call(params: {}, context: { actor_id: 7 })

      expect(received_context[:actor_id]).to eq(7)
    end

    it "does not merge non-Hash result values into rollback params" do
      received_params = nil

      svc = Class.new(Railsmith::BaseService) do
        def go = Railsmith::Result.success(value: "some-string")
        define_method(:undo) do
          received_params = params
          Railsmith::Result.success
        end
      end
      fail_svc = failure_service(:go)

      build_pipeline do
        step :s1, service: svc,      action: :go, rollback: :undo
        step :s2, service: fail_svc, action: :go
      end.call(params: { original: true })

      expect(received_params).to eq({ original: true })
    end
  end

  # ---------------------------------------------------------------------------
  # Rollback handler invocation — Proc
  # ---------------------------------------------------------------------------

  describe "proc rollback" do
    it "calls the proc with (step_result, context)" do
      received = {}

      svc = success_service(:go, value: { order_id: 5 })
      fail_svc = failure_service(:go)

      rollback_proc = lambda do |step_result, ctx|
        received[:result]  = step_result
        received[:context] = ctx
        Railsmith::Result.success
      end

      build_pipeline do
        step :s1, service: svc,      action: :go, rollback: rollback_proc
        step :s2, service: fail_svc, action: :go
      end.call(params: {}, context: { actor_id: 3 })

      expect(received[:result].value).to eq({ order_id: 5 })
      expect(received[:context][:actor_id]).to eq(3)
    end

    it "treats a nil proc return as success" do
      svc      = success_service(:go)
      fail_svc = failure_service(:go)

      silent_proc = ->(_r, _c) { nil }

      pipeline = build_pipeline do
        step :s1, service: svc,      action: :go, rollback: silent_proc
        step :s2, service: fail_svc, action: :go
      end

      result = pipeline.call(params: {})
      expect(result.meta).not_to have_key(:rollback_failures)
    end

    it "captures an exception raised inside the proc as a rollback failure" do
      svc      = success_service(:go)
      fail_svc = failure_service(:go)

      exploding_proc = ->(_r, _c) { raise "proc blew up" }

      pipeline = build_pipeline do
        step :s1, service: svc,      action: :go, rollback: exploding_proc
        step :s2, service: fail_svc, action: :go
      end

      result = pipeline.call(params: {})
      expect(result.meta[:rollback_failures]).to be_an(Array)
      expect(result.meta[:rollback_failures].first[:error].message).to eq("proc blew up")
    end
  end

  # ---------------------------------------------------------------------------
  # Rollback failures in result meta
  # ---------------------------------------------------------------------------

  describe "rollback failures" do
    it "attaches :rollback_failures to result meta when a rollback fails" do
      svc = Class.new(Railsmith::BaseService) do
        def go   = Railsmith::Result.success(value: { id: 1 })
        def undo  = Railsmith::Result.failure(code: :unexpected, message: "rollback broke")
      end
      fail_svc = failure_service(:go)

      pipeline = build_pipeline do
        step :s1, service: svc,      action: :go, rollback: :undo
        step :s2, service: fail_svc, action: :go
      end

      result = pipeline.call(params: {})
      expect(result.meta[:rollback_failures]).to be_an(Array)
      expect(result.meta[:rollback_failures].size).to eq(1)

      rf = result.meta[:rollback_failures].first
      expect(rf[:step]).to eq(:s1)
      expect(rf[:error].message).to eq("rollback broke")
    end

    it "omits :rollback_failures when all rollbacks succeed" do
      svc = Class.new(Railsmith::BaseService) do
        def go   = Railsmith::Result.success
        def undo  = Railsmith::Result.success
      end
      fail_svc = failure_service(:go)

      pipeline = build_pipeline do
        step :s1, service: svc,      action: :go, rollback: :undo
        step :s2, service: fail_svc, action: :go
      end

      result = pipeline.call(params: {})
      expect(result.meta).not_to have_key(:rollback_failures)
    end

    it "continues rolling back subsequent steps even when one rollback fails" do
      rolled_back = []

      svc_a = Class.new(Railsmith::BaseService) do
        def go   = Railsmith::Result.success
        define_method(:undo) do
          rolled_back << :a
          Railsmith::Result.success
        end
      end
      svc_b = Class.new(Railsmith::BaseService) do
        def go   = Railsmith::Result.success
        define_method(:undo) do
          rolled_back << :b
          Railsmith::Result.failure(message: "b rollback failed")
        end
      end
      fail_svc = failure_service(:go)

      build_pipeline do
        step :step_a, service: svc_a,    action: :go, rollback: :undo
        step :step_b, service: svc_b,    action: :go, rollback: :undo
        step :step_c, service: fail_svc, action: :go
      end.call(params: {})

      # b runs first (reverse), fails, then a still runs
      expect(rolled_back).to eq([:b, :a])
    end

    it "collects all rollback failures when multiple rollbacks fail" do
      svc_a = Class.new(Railsmith::BaseService) do
        def go   = Railsmith::Result.success
        def undo  = Railsmith::Result.failure(message: "a failed")
      end
      svc_b = Class.new(Railsmith::BaseService) do
        def go   = Railsmith::Result.success
        def undo  = Railsmith::Result.failure(message: "b failed")
      end
      fail_svc = failure_service(:go)

      pipeline = build_pipeline do
        step :step_a, service: svc_a,    action: :go, rollback: :undo
        step :step_b, service: svc_b,    action: :go, rollback: :undo
        step :fails,  service: fail_svc, action: :go
      end

      result = pipeline.call(params: {})
      messages = result.meta[:rollback_failures].map { |f| f[:error].message }
      expect(messages).to contain_exactly("a failed", "b failed")
    end

    it "preserves the primary failure error regardless of rollback outcome" do
      svc = Class.new(Railsmith::BaseService) do
        def go   = Railsmith::Result.success
        def undo  = Railsmith::Result.failure(message: "rollback error")
      end
      fail_svc = failure_service(:go, code: :not_found, message: "primary error")

      pipeline = build_pipeline do
        step :s1, service: svc,      action: :go, rollback: :undo
        step :s2, service: fail_svc, action: :go
      end

      result = pipeline.call(params: {})
      expect(result.error.message).to eq("primary error")
      expect(result.error.code).to    eq("not_found")
    end

    it "still sets :pipeline_name and :pipeline_step when rollbacks fail" do
      svc = Class.new(Railsmith::BaseService) do
        def go   = Railsmith::Result.success
        def undo  = Railsmith::Result.failure(message: "rb fail")
      end
      stub_const("RollbackPipeline", Class.new(Railsmith::Pipeline) do
        step :s1, service: Class.new(Railsmith::BaseService) {
          def go  = Railsmith::Result.success
          def undo = Railsmith::Result.failure(message: "rb fail")
        }, action: :go, rollback: :undo
        step :boom, service: Class.new(Railsmith::BaseService) {
          def go = Railsmith::Result.failure(message: "primary")
        }, action: :go
      end)

      result = RollbackPipeline.call(params: {})
      expect(result.meta[:pipeline_name]).to eq("RollbackPipeline")
      expect(result.meta[:pipeline_step]).to eq(:boom)
    end
  end

  # ---------------------------------------------------------------------------
  # Rollback instrumentation
  # ---------------------------------------------------------------------------

  describe "rollback instrumentation" do
    it "emits a pipeline.rollback.railsmith event for each rollback invoked" do
      events = []
      Railsmith::Instrumentation.subscribe("pipeline.rollback.railsmith") { |_, p| events << p }

      svc_a = Class.new(Railsmith::BaseService) do
        def go   = Railsmith::Result.success
        def undo  = Railsmith::Result.success
      end
      svc_b = Class.new(Railsmith::BaseService) do
        def go   = Railsmith::Result.success
        def undo  = Railsmith::Result.success
      end
      fail_svc = failure_service(:go)

      build_pipeline do
        step :step_a, service: svc_a,    action: :go, rollback: :undo
        step :step_b, service: svc_b,    action: :go, rollback: :undo
        step :fails,  service: fail_svc, action: :go
      end.call(params: {})

      expect(events.map { |e| e[:step] }).to eq(%i[step_b step_a])
    end

    it "emits :success status for a successful rollback" do
      events = []
      Railsmith::Instrumentation.subscribe("pipeline.rollback.railsmith") { |_, p| events << p }

      svc = Class.new(Railsmith::BaseService) do
        def go   = Railsmith::Result.success
        def undo  = Railsmith::Result.success
      end
      fail_svc = failure_service(:go)

      build_pipeline do
        step :s1, service: svc,      action: :go, rollback: :undo
        step :s2, service: fail_svc, action: :go
      end.call(params: {})

      expect(events.first[:status]).to eq(:success)
    end

    it "emits :failure status for a failed rollback" do
      events = []
      Railsmith::Instrumentation.subscribe("pipeline.rollback.railsmith") { |_, p| events << p }

      svc = Class.new(Railsmith::BaseService) do
        def go   = Railsmith::Result.success
        def undo  = Railsmith::Result.failure(message: "bad")
      end
      fail_svc = failure_service(:go)

      build_pipeline do
        step :s1, service: svc,      action: :go, rollback: :undo
        step :s2, service: fail_svc, action: :go
      end.call(params: {})

      expect(events.first[:status]).to eq(:failure)
    end

    it "includes :pipeline, :step, and numeric :duration in the rollback event" do
      events = []
      Railsmith::Instrumentation.subscribe("pipeline.rollback.railsmith") { |_, p| events << p }

      stub_const("RbInstrPipeline", Class.new(Railsmith::Pipeline) do
        step :s1,
          service: Class.new(Railsmith::BaseService) {
            def go   = Railsmith::Result.success
            def undo  = Railsmith::Result.success
          },
          action: :go, rollback: :undo
        step :boom,
          service: Class.new(Railsmith::BaseService) {
            def go = Railsmith::Result.failure(message: "fail")
          },
          action: :go
      end)

      RbInstrPipeline.call(params: {})

      event = events.first
      expect(event[:pipeline]).to eq("RbInstrPipeline")
      expect(event[:step]).to     eq(:s1)
      expect(event[:duration]).to be_a(Numeric)
    end

    it "does not emit rollback events when no steps have rollback declared" do
      events = []
      Railsmith::Instrumentation.subscribe("pipeline.rollback.railsmith") { |_, p| events << p }

      svc      = success_service(:go)
      fail_svc = failure_service(:go)

      build_pipeline do
        step :s1, service: svc,      action: :go
        step :s2, service: fail_svc, action: :go
      end.call(params: {})

      expect(events).to be_empty
    end

    it "does not emit rollback events when the pipeline succeeds" do
      events = []
      Railsmith::Instrumentation.subscribe("pipeline.rollback.railsmith") { |_, p| events << p }

      svc = Class.new(Railsmith::BaseService) do
        def go   = Railsmith::Result.success
        def undo  = Railsmith::Result.success
      end

      build_pipeline do
        step :s1, service: svc, action: :go, rollback: :undo
      end.call(params: {})

      expect(events).to be_empty
    end
  end
end
