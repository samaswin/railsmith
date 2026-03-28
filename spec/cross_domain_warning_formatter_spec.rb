# frozen_string_literal: true

require "json"
require "spec_helper"

RSpec.describe Railsmith::CrossDomainWarningFormatter do
  let(:payload) do
    {
      event: "cross_domain.warning",
      context_domain: :billing,
      service_domain: :catalog,
      service: "Catalog::ItemService",
      action: :create,
      strict_mode: false,
      blocking: false,
      occurred_at: "2026-03-28T12:00:00.000000Z"
    }
  end

  describe ".as_json_line" do
    it "produces a single line of JSON with canonical keys first" do
      line = described_class.as_json_line(payload)
      expect(line).not_to include("\n")
      parsed = JSON.parse(line)
      expect(parsed.keys.first(8)).to eq(
        %w[
          event
          context_domain
          service_domain
          service
          action
          strict_mode
          blocking
          occurred_at
        ]
      )
      expect(parsed["context_domain"]).to eq("billing")
      expect(parsed["service_domain"]).to eq("catalog")
    end

    it "appends extra keys after canonical keys" do
      extended = payload.merge(extra_note: "sync")
      line = described_class.as_json_line(extended)
      parsed = JSON.parse(line)
      keys = parsed.keys
      expect(keys.index("extra_note")).to be > keys.index("occurred_at")
    end
  end

  describe ".as_key_value_line" do
    it "renders key=value pairs with JSON-encoded values" do
      line = described_class.as_key_value_line(payload)
      expect(line).to include('event="cross_domain.warning"')
      expect(line).to include("context_domain=")
      expect(line).to include('"billing"')
      expect(line).not_to include("\n")
    end
  end

  describe "nil values" do
    it "omits nil values from as_json_line" do
      sparse = payload.merge(strict_mode: nil)
      parsed = JSON.parse(described_class.as_json_line(sparse))
      expect(parsed).not_to have_key("strict_mode")
    end

    it "omits nil values from as_key_value_line" do
      sparse = payload.merge(strict_mode: nil)
      line = described_class.as_key_value_line(sparse)
      expect(line).not_to include("strict_mode=")
    end
  end

  describe "integration with on_cross_domain_violation" do
    after { Railsmith::Instrumentation.reset! }

    it "formats the violation payload received by the callback as a JSON line" do
      received_line = nil
      Railsmith.configure do |config|
        config.strict_mode = true
        config.on_cross_domain_violation = lambda { |p|
          received_line = Railsmith::CrossDomainWarningFormatter.as_json_line(p)
        }
      end

      service_class = Class.new(Railsmith::BaseService) do
        service_domain :catalog

        def create
          Railsmith::Result.success(value: {})
        end
      end

      service_class.call(action: :create, params: {}, context: { current_domain: :billing })

      expect(received_line).not_to be_nil
      parsed = JSON.parse(received_line)
      expect(parsed["event"]).to eq("cross_domain.warning")
      expect(parsed["context_domain"]).to eq("billing")
      expect(parsed["service_domain"]).to eq("catalog")
      expect(parsed["blocking"]).to be false
    ensure
      Railsmith.configuration = Railsmith::Configuration.new
    end
  end
end
