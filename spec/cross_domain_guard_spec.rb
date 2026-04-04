# frozen_string_literal: true

require "spec_helper"

RSpec.describe Railsmith::CrossDomainGuard do
  after do
    Railsmith::Instrumentation.reset!
    Railsmith.configuration = Railsmith::Configuration.new
  end

  describe ".allowed_crossing?" do
    it "returns true when a hash entry matches from/to domains" do
      allowlist = [{ from: :billing, to: :catalog }]
      expect(described_class.allowed_crossing?(allowlist, :billing, :catalog)).to be true
    end

    it "accepts string keys in hash entries" do
      allowlist = [{ "from" => "billing", "to" => "catalog" }]
      expect(described_class.allowed_crossing?(allowlist, :billing, :catalog)).to be true
    end

    it "returns true when a two-element array matches" do
      allowlist = [%i[billing catalog]]
      expect(described_class.allowed_crossing?(allowlist, :billing, :catalog)).to be true
    end

    it "returns false when no entry matches" do
      allowlist = [{ from: :billing, to: :inventory }]
      expect(described_class.allowed_crossing?(allowlist, :billing, :catalog)).to be false
    end

    it "returns false for arrays that are not pairs" do
      expect(described_class.allowed_crossing?([%i[billing]], :billing, :catalog)).to be false
    end

    it "returns false for unknown entry types" do
      expect(described_class.allowed_crossing?([:billing], :billing, :catalog)).to be false
    end
  end

  describe ".pair_matches?" do
    it "matches hash pairs with symbol keys" do
      expect(described_class.pair_matches?({ from: :a, to: :b }, :a, :b)).to be true
    end

    it "normalizes string domains in hash entries" do
      expect(described_class.pair_matches?({ from: "a", to: "b" }, :a, :b)).to be true
    end

    it "matches two-element arrays" do
      expect(described_class.pair_matches?(%i[a b], :a, :b)).to be true
    end
  end

  describe ".domain_mismatch" do
    it "returns both domains when they differ and are present" do
      service_class = Class.new(Railsmith::BaseService) do
        service_domain :catalog
      end

      instance = service_class.new(params: {}, context: { current_domain: :billing })
      expect(described_class.domain_mismatch(instance)).to eq(
        context_domain: :billing,
        service_domain: :catalog
      )
    end

    it "returns nil when domains match" do
      service_class = Class.new(Railsmith::BaseService) do
        service_domain :billing
      end

      instance = service_class.new(params: {}, context: { current_domain: :billing })
      expect(described_class.domain_mismatch(instance)).to be_nil
    end

    it "returns nil when service_domain is not declared" do
      service_class = Class.new(Railsmith::BaseService)

      instance = service_class.new(params: {}, context: { current_domain: :billing })
      expect(described_class.domain_mismatch(instance)).to be_nil
    end
  end

  describe ".build_payload" do
    it "returns a stable, structured hash" do
      payload = described_class.build_payload(
        context_domain: :billing,
        service_domain: :catalog,
        service: "Catalog::ItemService",
        action: :create,
        strict_mode: false
      )

      expect(payload.except(:occurred_at)).to eq(
        event: "cross_domain.warning",
        context_domain: :billing,
        service_domain: :catalog,
        service: "Catalog::ItemService",
        action: :create,
        strict_mode: false,
        blocking: false
      )
      expect(payload[:occurred_at]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end

    it "uses a microsecond-precision UTC timestamp" do
      Timecop.freeze(Time.utc(2026, 3, 28, 12, 0, 0)) do
        payload = described_class.build_payload(
          context_domain: :billing,
          service_domain: :catalog,
          service: "S",
          action: :create,
          strict_mode: false
        )
        expect(payload[:occurred_at]).to eq("2026-03-28T12:00:00.000000Z")
      end
    end
  end

  describe ".emit_if_violation" do
    let(:configuration) { Railsmith::Configuration.new }

    before do
      Railsmith.configuration = configuration
    end

    it "emits cross_domain.warning when context and service domains differ" do
      warnings = []
      Railsmith::Instrumentation.subscribe("cross_domain.warning") { |_name, payload| warnings << payload }

      service_class = Class.new(Railsmith::BaseService) do
        service_domain :catalog

        def create
          Railsmith::Result.success(value: { ok: true })
        end
      end

      result = service_class.call(action: :create, params: {}, context: { current_domain: :billing })
      expect(result).to be_success
      expect(warnings.size).to eq(1)
      expect(warnings.first[:context_domain]).to eq(:billing)
      expect(warnings.first[:service_domain]).to eq(:catalog)
      expect(warnings.first[:blocking]).to be false
      expect(warnings.first[:log_json_line]).to eq(
        Railsmith::CrossDomainWarningFormatter.as_json_line(warnings.first.except(:log_json_line, :log_kv_line))
      )
      expect(warnings.first[:log_kv_line]).to eq(
        Railsmith::CrossDomainWarningFormatter.as_key_value_line(warnings.first.except(:log_json_line, :log_kv_line))
      )
    end

    it "dispatches cross_domain.warning.railsmith to plain Ruby subscribers" do
      events = []
      Railsmith::Instrumentation.subscribe { |full_name, payload| events << [full_name, payload] }

      service_class = Class.new(Railsmith::BaseService) do
        service_domain :catalog

        def create
          Railsmith::Result.success(value: {})
        end
      end

      service_class.call(action: :create, params: {}, context: { current_domain: :billing })

      pair = events.assoc("cross_domain.warning.railsmith")
      expect(pair).not_to be_nil
      expect(pair.last[:event]).to eq("cross_domain.warning")
    end

    it "does not emit when the crossing is allowlisted" do
      warnings = []
      Railsmith::Instrumentation.subscribe("cross_domain.warning") { |_name, payload| warnings << payload }
      configuration.cross_domain_allowlist = [%i[billing catalog]]

      service_class = Class.new(Railsmith::BaseService) do
        service_domain :catalog

        def create
          Railsmith::Result.success(value: {})
        end
      end

      service_class.call(action: :create, params: {}, context: { current_domain: :billing })
      expect(warnings).to be_empty
    end

    it "does not emit when warn_on_cross_domain_calls is false" do
      configuration.warn_on_cross_domain_calls = false
      warnings = []
      Railsmith::Instrumentation.subscribe("cross_domain.warning") { |_name, payload| warnings << payload }

      service_class = Class.new(Railsmith::BaseService) do
        service_domain :catalog

        def create
          Railsmith::Result.success(value: {})
        end
      end

      service_class.call(action: :create, params: {}, context: { current_domain: :billing })
      expect(warnings).to be_empty
    end

    it "does not emit when context domain is blank" do
      warnings = []
      Railsmith::Instrumentation.subscribe("cross_domain.warning") { |_name, payload| warnings << payload }

      service_class = Class.new(Railsmith::BaseService) do
        service_domain :catalog

        def create
          Railsmith::Result.success(value: {})
        end
      end

      service_class.call(action: :create, params: {}, context: {})
      expect(warnings).to be_empty
    end

    it "does not emit when service_domain is not declared" do
      warnings = []
      Railsmith::Instrumentation.subscribe("cross_domain.warning") { |_name, payload| warnings << payload }

      service_class = Class.new(Railsmith::BaseService) do
        def create
          Railsmith::Result.success(value: {})
        end
      end

      service_class.call(action: :create, params: {}, context: { current_domain: :billing })
      expect(warnings).to be_empty
    end

    it "invokes on_cross_domain_violation when strict_mode is enabled without blocking the call" do
      received = nil
      configuration.strict_mode = true
      configuration.on_cross_domain_violation = ->(payload) { received = payload }

      service_class = Class.new(Railsmith::BaseService) do
        service_domain :catalog

        def create
          Railsmith::Result.success(value: { done: true })
        end
      end

      result = service_class.call(action: :create, params: {}, context: { current_domain: :billing })
      expect(result).to be_success
      expect(result.value).to eq({ done: true })
      expect(received[:context_domain]).to eq(:billing)
      expect(received[:service_domain]).to eq(:catalog)
      expect(received[:blocking]).to be false
    end

    it "does not invoke on_cross_domain_violation when strict_mode is false" do
      called = false
      configuration.strict_mode = false
      configuration.on_cross_domain_violation = ->(_payload) { called = true }

      service_class = Class.new(Railsmith::BaseService) do
        service_domain :catalog

        def create
          Railsmith::Result.success(value: {})
        end
      end

      service_class.call(action: :create, params: {}, context: { current_domain: :billing })
      expect(called).to be false
    end

    it "still emits warning event when strict_mode is true but on_cross_domain_violation is nil" do
      warnings = []
      configuration.strict_mode = true
      configuration.on_cross_domain_violation = nil
      Railsmith::Instrumentation.subscribe("cross_domain.warning") { |_name, payload| warnings << payload }

      service_class = Class.new(Railsmith::BaseService) do
        service_domain :catalog

        def create
          Railsmith::Result.success(value: {})
        end
      end

      result = service_class.call(action: :create, params: {}, context: { current_domain: :billing })
      expect(result).to be_success
      expect(warnings.size).to eq(1)
    end

    it "does not emit when context domain is a blank string" do
      warnings = []
      Railsmith::Instrumentation.subscribe("cross_domain.warning") { |_name, payload| warnings << payload }

      service_class = Class.new(Railsmith::BaseService) do
        service_domain :catalog

        def create
          Railsmith::Result.success(value: {})
        end
      end

      service_class.call(action: :create, params: {}, context: { current_domain: "" })
      expect(warnings).to be_empty
    end
  end

  describe "service_domain inheritance" do
    it "does not inherit service_domain from a parent class" do
      parent = Class.new(Railsmith::BaseService) do
        service_domain :catalog
      end
      child = Class.new(parent)

      expect(child.service_domain).to be_nil
    end

    it "does not emit a warning for a subclass with no service_domain declared" do
      warnings = []
      Railsmith::Instrumentation.subscribe("cross_domain.warning") { |_name, payload| warnings << payload }

      parent = Class.new(Railsmith::BaseService) do
        service_domain :catalog
      end
      child = Class.new(parent) do
        def create
          Railsmith::Result.success(value: {})
        end
      end

      child.call(action: :create, params: {}, context: { current_domain: :billing })
      expect(warnings).to be_empty
    end
  end
end
