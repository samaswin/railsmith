# frozen_string_literal: true

require "spec_helper"

RSpec.describe Railsmith::Instrumentation do
  after { described_class.reset! }

  describe ".instrument" do
    it "returns the block result" do
      result = described_class.instrument("test.event", { a: 1 }) { :done }
      expect(result).to eq(:done)
    end

    it "yields before notifying plain Ruby subscribers" do
      order = []
      described_class.subscribe { order << :notified }
      described_class.instrument("phase", {}) { order << :block }

      expect(order).to eq(%i[block notified])
    end

    it "dispatches the namespaced event name to subscribers" do
      names = []
      described_class.subscribe { |event_name, _| names << event_name }
      described_class.instrument("service.call", { domain: :x }) { nil }

      expect(names).to eq(["service.call.railsmith"])
    end

    it "passes the payload through to subscribers" do
      payloads = []
      described_class.subscribe { |_, payload| payloads << payload }
      described_class.instrument("service.call", { domain: :billing, action: :create }) { nil }

      expect(payloads.first).to eq({ domain: :billing, action: :create })
    end
  end

  describe ".subscribe" do
    it "ignores events when the pattern is not a prefix of the full event name" do
      payloads = []
      described_class.subscribe("other") { |_, p| payloads << p }
      described_class.instrument("service.call", {}) { nil }

      expect(payloads).to be_empty
    end

    it "delivers events when the pattern matches the start of the full name" do
      payloads = []
      described_class.subscribe("service.call") { |_, p| payloads << p }
      described_class.instrument("service.call", { ok: true }) { nil }

      expect(payloads.size).to eq(1)
      expect(payloads.first[:ok]).to be true
    end
  end

  describe ".reset!" do
    it "clears plain Ruby subscribers" do
      described_class.subscribe { |_e, _p| nil }
      described_class.reset!
      count = 0
      described_class.instrument("x", {}) { count += 1 }

      expect(count).to eq(1)
    end
  end
end
