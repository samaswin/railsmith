# frozen_string_literal: true

require "spec_helper"

RSpec.describe Railsmith::Pipeline do
  # ---------------------------------------------------------------------------
  # Helpers: lightweight stub services that return controlled results
  # ---------------------------------------------------------------------------

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

  # Convenience: build a one-off pipeline class with the given steps block
  def build_pipeline(&steps_block)
    Class.new(Railsmith::Pipeline, &steps_block)
  end

  after { Railsmith::Instrumentation.reset! }

  # ---------------------------------------------------------------------------
  # 3.1 Pipeline Base Class
  # ---------------------------------------------------------------------------

  describe ".step" do
    it "registers a StepDefinition on the class" do
      svc = success_service(:create)
      pipeline = build_pipeline { step :create_thing, service: svc, action: :create }

      expect(pipeline.step_definitions.size).to eq(1)
      defn = pipeline.step_definitions.first
      expect(defn.name).to   eq(:create_thing)
      expect(defn.service).to be(svc)
      expect(defn.action).to  eq(:create)
      expect(defn.inputs).to  be_nil
    end

    it "preserves declaration order" do
      svc = success_service(:go)
      pipeline = build_pipeline do
        step :first,  service: svc, action: :go
        step :second, service: svc, action: :go
        step :third,  service: svc, action: :go
      end

      expect(pipeline.step_definitions.map(&:name)).to eq(%i[first second third])
    end

    it "coerces name and action to symbols" do
      svc = success_service(:run)
      pipeline = build_pipeline { step "run_it", service: svc, action: "run" }

      defn = pipeline.step_definitions.first
      expect(defn.name).to   eq(:run_it)
      expect(defn.action).to eq(:run)
    end
  end

  describe ".pipeline_name" do
    it "returns the class name when named" do
      stub_const("MyPipeline", Class.new(Railsmith::Pipeline))
      expect(MyPipeline.pipeline_name).to eq("MyPipeline")
    end

    it "returns AnonymousPipeline for anonymous classes" do
      expect(build_pipeline {}.pipeline_name).to eq("AnonymousPipeline")
    end
  end

  describe ".inherited" do
    it "gives the subclass an independent copy of steps" do
      svc = success_service(:go)
      parent = build_pipeline { step :from_parent, service: svc, action: :go }
      child  = Class.new(parent)
      child.step :from_child, service: svc, action: :go

      expect(parent.step_definitions.map(&:name)).to eq(%i[from_parent])
      expect(child.step_definitions.map(&:name)).to  eq(%i[from_parent from_child])
    end
  end

  # ---------------------------------------------------------------------------
  # 3.1 / call interface
  # ---------------------------------------------------------------------------

  describe ".call" do
    it "returns a success Result when all steps succeed" do
      svc = success_service(:run, value: { ok: true })
      pipeline = build_pipeline { step :do_it, service: svc, action: :run }

      result = pipeline.call(params: {})
      expect(result).to be_success
    end

    it "returns the last step's Result value" do
      svc = success_service(:run, value: { final: 42 })
      pipeline = build_pipeline { step :last, service: svc, action: :run }

      result = pipeline.call(params: {})
      expect(result.value).to eq({ final: 42 })
    end

    it "returns success with nil value for an empty pipeline" do
      pipeline = build_pipeline {}
      result   = pipeline.call(params: { x: 1 })
      expect(result).to be_success
      expect(result.value).to be_nil
    end
  end

  describe ".call!" do
    it "returns the Result on success" do
      svc    = success_service(:go)
      pipeline = build_pipeline { step :s, service: svc, action: :go }
      expect { pipeline.call! }.not_to raise_error
    end

    it "raises Railsmith::Failure on failure" do
      svc = failure_service(:go)
      pipeline = build_pipeline { step :s, service: svc, action: :go }
      expect { pipeline.call! }.to raise_error(Railsmith::Failure)
    end
  end

  # ---------------------------------------------------------------------------
  # 3.2 Param Forwarding
  # ---------------------------------------------------------------------------

  describe "param forwarding" do
    it "forwards original params to the first step" do
      received = nil
      svc = Class.new(Railsmith::BaseService) do
        define_method(:run) do
          received = params
          Railsmith::Result.success
        end
      end

      build_pipeline { step :s, service: svc, action: :run }
        .call(params: { cart_id: 99 })

      expect(received).to include(cart_id: 99)
    end

    it "merges previous step's Hash result.value into accumulated params" do
      received = nil
      step1_svc = success_service(:go, value: { order_id: 7 })
      step2_svc = Class.new(Railsmith::BaseService) do
        define_method(:go) do
          received = params
          Railsmith::Result.success
        end
      end

      build_pipeline do
        step :step1, service: step1_svc, action: :go
        step :step2, service: step2_svc, action: :go
      end.call(params: { cart_id: 1 })

      expect(received).to include(cart_id: 1, order_id: 7)
    end

    it "accumulates params across multiple steps" do
      received = nil
      svc_a = success_service(:go, value: { a: 1 })
      svc_b = success_service(:go, value: { b: 2 })
      svc_c = Class.new(Railsmith::BaseService) do
        define_method(:go) do
          received = params
          Railsmith::Result.success
        end
      end

      build_pipeline do
        step :step_a, service: svc_a, action: :go
        step :step_b, service: svc_b, action: :go
        step :step_c, service: svc_c, action: :go
      end.call(params: { x: 0 })

      expect(received).to include(x: 0, a: 1, b: 2)
    end

    it "does not merge non-Hash result values" do
      received = nil
      svc_a = success_service(:go, value: "some_string")
      svc_b = Class.new(Railsmith::BaseService) do
        define_method(:go) do
          received = params
          Railsmith::Result.success
        end
      end

      build_pipeline do
        step :step_a, service: svc_a, action: :go
        step :step_b, service: svc_b, action: :go
      end.call(params: { original: true })

      expect(received).to eq({ original: true })
    end

    context "inputs: renaming" do
      it "renames the specified key before passing to the step" do
        received = nil
        svc = Class.new(Railsmith::BaseService) do
          define_method(:go) do
            received = params
            Railsmith::Result.success
          end
        end

        build_pipeline do
          step :s, service: svc, action: :go, inputs: { amount: :cart_total }
        end.call(params: { cart_total: 100, user_id: 5 })

        expect(received).to include(amount: 100, user_id: 5)
        expect(received).not_to have_key(:cart_total)
      end

      it "leaves accumulated params unchanged after the rename step" do
        received_second = nil
        first_svc = success_service(:go, value: { cart_total: 200 })
        rename_svc = success_service(:go)
        third_svc = Class.new(Railsmith::BaseService) do
          define_method(:go) do
            received_second = params
            Railsmith::Result.success
          end
        end

        build_pipeline do
          step :first,  service: first_svc,  action: :go
          step :rename, service: rename_svc, action: :go, inputs: { amount: :cart_total }
          step :third,  service: third_svc,  action: :go
        end.call(params: {})

        # :cart_total should still be in accumulated params for the third step
        expect(received_second).to include(cart_total: 200)
      end

      it "raises ParamMappingError when source key is absent" do
        svc = success_service(:go)
        pipeline = build_pipeline do
          step :s, service: svc, action: :go, inputs: { x: :missing_key }
        end

        expect { pipeline.call(params: {}) }
          .to raise_error(Railsmith::Pipeline::ParamMappingError, /:missing_key/)
      end

      it "is a no-op when target and source key are identical" do
        received = nil
        svc = Class.new(Railsmith::BaseService) do
          define_method(:go) do
            received = params
            Railsmith::Result.success
          end
        end

        build_pipeline do
          step :s, service: svc, action: :go, inputs: { foo: :foo }
        end.call(params: { foo: 42 })

        expect(received).to include(foo: 42)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 3.3 Fail-Fast
  # ---------------------------------------------------------------------------

  describe "fail-fast behavior" do
    it "halts on the first failing step" do
      calls = []
      track = lambda do |label, result|
        Class.new(Railsmith::BaseService) do
          define_method(:go) do
            calls << label
            result
          end
        end
      end

      svc_a = track.call(:a, Railsmith::Result.success)
      svc_b = track.call(:b, Railsmith::Result.failure(message: "boom"))
      svc_c = track.call(:c, Railsmith::Result.success)

      build_pipeline do
        step :step_a, service: svc_a, action: :go
        step :step_b, service: svc_b, action: :go
        step :step_c, service: svc_c, action: :go
      end.call(params: {})

      expect(calls).to eq([:a, :b])
    end

    it "returns a failure Result" do
      svc = failure_service(:go, message: "bad input")
      pipeline = build_pipeline { step :s, service: svc, action: :go }

      result = pipeline.call(params: {})
      expect(result).to be_failure
      expect(result.error.message).to eq("bad input")
    end

    it "attaches :pipeline_name to the failure meta" do
      stub_const("FailingPipeline", Class.new(Railsmith::Pipeline) do
        step :s, service: Class.new(Railsmith::BaseService) {
          def go = Railsmith::Result.failure(message: "oops")
        }, action: :go
      end)

      result = FailingPipeline.call(params: {})
      expect(result.meta[:pipeline_name]).to eq("FailingPipeline")
    end

    it "attaches :pipeline_step to the failure meta" do
      svc = failure_service(:go)
      pipeline = build_pipeline { step :broken_step, service: svc, action: :go }

      result = pipeline.call(params: {})
      expect(result.meta[:pipeline_step]).to eq(:broken_step)
    end

    it "preserves the original error payload on failure" do
      svc = failure_service(:go, code: :not_found, message: "Cart not found")
      pipeline = build_pipeline { step :s, service: svc, action: :go }

      result = pipeline.call(params: {})
      expect(result.error.code).to    eq("not_found")
      expect(result.error.message).to eq("Cart not found")
    end
  end

  # ---------------------------------------------------------------------------
  # 3.4 Instrumentation
  # ---------------------------------------------------------------------------

  describe "instrumentation" do
    it "emits a pipeline.step.railsmith event for each step" do
      events = []
      Railsmith::Instrumentation.subscribe("pipeline.step.railsmith") do |name, payload|
        events << payload
      end

      svc = success_service(:go, value: { x: 1 })
      build_pipeline do
        step :step_one, service: svc, action: :go
        step :step_two, service: svc, action: :go
      end.call(params: {})

      expect(events.map { |e| e[:step] }).to eq(%i[step_one step_two])
    end

    it "emits :success status on successful steps" do
      events = []
      Railsmith::Instrumentation.subscribe("pipeline.step.railsmith") do |_, payload|
        events << payload
      end

      svc = success_service(:go)
      build_pipeline { step :s, service: svc, action: :go }.call(params: {})

      expect(events.first[:status]).to eq(:success)
    end

    it "emits :failure status on failing steps" do
      events = []
      Railsmith::Instrumentation.subscribe("pipeline.step.railsmith") do |_, payload|
        events << payload
      end

      svc = failure_service(:go)
      build_pipeline { step :s, service: svc, action: :go }.call(params: {})

      expect(events.first[:status]).to eq(:failure)
    end

    it "emits a pipeline.railsmith event on completion" do
      events = []
      Railsmith::Instrumentation.subscribe("pipeline.railsmith") do |_, payload|
        events << payload
      end

      svc = success_service(:go)
      build_pipeline { step :s, service: svc, action: :go }.call(params: {})

      expect(events.size).to eq(1)
      expect(events.first[:status]).to eq(:success)
    end

    it "includes :pipeline name in step events" do
      stub_const("NamedPipeline", Class.new(Railsmith::Pipeline) do
        step :s, service: Class.new(Railsmith::BaseService) {
          def go = Railsmith::Result.success
        }, action: :go
      end)

      events = []
      Railsmith::Instrumentation.subscribe("pipeline.step.railsmith") do |_, payload|
        events << payload
      end

      NamedPipeline.call(params: {})
      expect(events.first[:pipeline]).to eq("NamedPipeline")
    end

    it "includes :duration (numeric) in step events" do
      events = []
      Railsmith::Instrumentation.subscribe("pipeline.step.railsmith") do |_, payload|
        events << payload
      end

      svc = success_service(:go)
      build_pipeline { step :s, service: svc, action: :go }.call(params: {})

      expect(events.first[:duration]).to be_a(Numeric)
    end

    it "emits the overall pipeline event even when a step fails" do
      events = []
      Railsmith::Instrumentation.subscribe("pipeline.railsmith") do |_, payload|
        events << payload
      end

      svc = failure_service(:go)
      build_pipeline { step :s, service: svc, action: :go }.call(params: {})

      expect(events.first[:status]).to eq(:failure)
    end
  end

  # ---------------------------------------------------------------------------
  # Context propagation
  # ---------------------------------------------------------------------------

  describe "context propagation" do
    it "passes the same context to every step" do
      contexts = []
      svc = Class.new(Railsmith::BaseService) do
        define_method(:go) do
          contexts << context
          Railsmith::Result.success
        end
      end

      build_pipeline do
        step :step_a, service: svc, action: :go
        step :step_b, service: svc, action: :go
      end.call(params: {}, context: { actor_id: 42 })

      expect(contexts.map { |c| c[:actor_id] }).to all(eq(42))
    end
  end
end
