# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Railsmith::BaseService domain context propagation" do
  after do
    Railsmith::Instrumentation.reset!
    Railsmith.configuration = Railsmith::Configuration.new
  end

  describe "#current_domain" do
    it "exposes the domain key from context" do
      service_class = Class.new(Railsmith::BaseService) do
        def probe
          Railsmith::Result.success(value: { domain: current_domain })
        end
      end

      result = service_class.call(action: :probe, params: {}, context: { current_domain: :billing })
      expect(result).to be_success
      expect(result.value[:domain]).to eq(:billing)
    end

    it "returns nil when domain is not set (flexible mode allows this)" do
      service_class = Class.new(Railsmith::BaseService) do
        def probe
          Railsmith::Result.success(value: { domain: current_domain })
        end
      end

      result = service_class.call(action: :probe, params: {}, context: {})
      expect(result).to be_success
      expect(result.value[:domain]).to be_nil
    end

    it "returns nil when context is blank (flexible mode)" do
      service_class = Class.new(Railsmith::BaseService) do
        def probe
          Railsmith::Result.success(value: { domain: current_domain })
        end
      end

      result = service_class.call(action: :probe, params: {}, context: {})
      expect(result.value[:domain]).to be_nil
    end

    it "normalizes a string current_domain to a symbol" do
      service_class = Class.new(Railsmith::BaseService) do
        def probe
          Railsmith::Result.success(value: { domain: current_domain })
        end
      end

      result = service_class.call(action: :probe, params: {}, context: { current_domain: "billing" })
      expect(result).to be_success
      expect(result.value[:domain]).to eq(:billing)
    end
  end

  describe "nested service calls" do
    it "preserves current_domain when an outer service passes context into an inner service" do
      inner = Class.new(Railsmith::BaseService) do
        def inner_probe
          Railsmith::Result.success(value: { inner: current_domain })
        end
      end

      outer = Class.new(Railsmith::BaseService) do
        define_method(:outer_probe) do
          inner.call(action: :inner_probe, params: {}, context: context)
        end
      end

      result = outer.call(
        action: :outer_probe,
        params: {},
        context: { current_domain: :inventory, trace_id: "t1" }
      )

      expect(result).to be_success
      expect(result.value[:inner]).to eq(:inventory)
    end
  end

  describe "instrumentation hooks" do
    it "emits a service.call.railsmith event with domain tag" do
      events = []
      Railsmith::Instrumentation.subscribe("service.call") do |_event, payload|
        events << payload
      end

      service_class = Class.new(Railsmith::BaseService) do
        def create
          Railsmith::Result.success(value: {})
        end
      end

      service_class.call(action: :create, params: {}, context: { current_domain: "catalog" })

      expect(events.size).to eq(1)
      expect(events.first[:domain]).to eq(:catalog)
      expect(events.first[:action]).to eq(:create)
    end

    it "emits a nil domain when domain is not set" do
      events = []
      Railsmith::Instrumentation.subscribe do |_event, payload|
        events << payload
      end

      service_class = Class.new(Railsmith::BaseService) do
        def create
          Railsmith::Result.success(value: {})
        end
      end

      service_class.call(action: :create, params: {}, context: {})

      expect(events.size).to eq(1)
      expect(events.first[:domain]).to be_nil
    end

    it "includes the service class name in the instrumentation payload" do
      events = []
      Railsmith::Instrumentation.subscribe { |_e, p| events << p }

      stub_const("Billing::InvoiceService", Class.new(Railsmith::BaseService) do
        def create
          Railsmith::Result.success(value: {})
        end
      end)

      Billing::InvoiceService.call(action: :create, params: {}, context: { current_domain: :billing })

      expect(events.first[:service]).to eq("Billing::InvoiceService")
    end

    it "does not suppress the action result when instrumentation is active" do
      Railsmith::Instrumentation.subscribe { |_e, _p| nil }

      service_class = Class.new(Railsmith::BaseService) do
        def create
          Railsmith::Result.success(value: { ok: true })
        end
      end

      result = service_class.call(action: :create, params: {}, context: { current_domain: :identity })
      expect(result).to be_success
      expect(result.value).to eq({ ok: true })
    end
  end

  describe "context immutability" do
    it "does not expose the original context object to mutation through the service" do
      original_context = { current_domain: :billing, actor_id: 1 }

      service_class = Class.new(Railsmith::BaseService) do
        def probe
          context[:current_domain] = :hacked
          Railsmith::Result.success(value: {})
        end
      end

      service_class.call(action: :probe, params: {}, context: original_context)
      expect(original_context[:current_domain]).to eq(:billing)
    end
  end

  describe "cross-domain guardrails (warn-only)" do
    it "still returns a successful result when a cross-domain warning fires" do
      Railsmith::Instrumentation.subscribe("cross_domain.warning") { |_e, _p| nil }

      service_class = Class.new(Railsmith::BaseService) do
        service_domain :catalog

        def create
          Railsmith::Result.success(value: { created: true })
        end
      end

      result = service_class.call(action: :create, params: {}, context: { current_domain: :billing })
      expect(result).to be_success
      expect(result.value).to eq({ created: true })
    end

    it "emits cross_domain.warning before service.call for ordering subscribers" do
      order = []
      Railsmith::Instrumentation.subscribe("cross_domain.warning") { order << :cross_domain }
      Railsmith::Instrumentation.subscribe("service.call") { order << :service_call }

      service_class = Class.new(Railsmith::BaseService) do
        service_domain :catalog

        def create
          Railsmith::Result.success(value: {})
        end
      end

      service_class.call(action: :create, params: {}, context: { current_domain: :billing })
      expect(order).to eq(%i[cross_domain service_call])
    end
  end
end
