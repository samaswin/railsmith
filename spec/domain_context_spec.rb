# frozen_string_literal: true

require "spec_helper"

RSpec.describe Railsmith::DomainContext do
  describe ".normalize_current_domain" do
    it "returns nil for nil and blank strings" do
      expect(described_class.normalize_current_domain(nil)).to be_nil
      expect(described_class.normalize_current_domain("")).to be_nil
      expect(described_class.normalize_current_domain("   ")).to be_nil
    end

    it "coerces strings to symbols" do
      expect(described_class.normalize_current_domain("billing")).to eq(:billing)
    end

    it "returns symbols unchanged" do
      expect(described_class.normalize_current_domain(:catalog)).to eq(:catalog)
    end
  end

  describe "#initialize" do
    it "stores current_domain as a symbol" do
      ctx = described_class.new(current_domain: "billing")
      expect(ctx.current_domain).to eq(:billing)
    end

    it "accepts a symbol directly" do
      ctx = described_class.new(current_domain: :catalog)
      expect(ctx.current_domain).to eq(:catalog)
    end

    it "allows nil domain (flexible mode)" do
      ctx = described_class.new
      expect(ctx.current_domain).to be_nil
    end

    it "treats a blank string domain as nil" do
      expect(described_class.new(current_domain: "").current_domain).to be_nil
    end

    it "freezes meta to prevent mutation" do
      ctx = described_class.new(meta: { request_id: "abc" })
      expect(ctx.meta).to be_frozen
    end

    it "treats nil meta the same as an empty hash" do
      ctx = described_class.new(meta: nil)
      expect(ctx.meta).to eq({})
    end
  end

  describe "#blank_domain?" do
    it "returns true when domain is nil" do
      expect(described_class.new.blank_domain?).to be true
    end

    it "returns false when domain is set" do
      expect(described_class.new(current_domain: :billing).blank_domain?).to be false
    end
  end

  describe "#to_h" do
    it "includes current_domain" do
      ctx = described_class.new(current_domain: :billing)
      expect(ctx.to_h).to include(current_domain: :billing)
    end

    it "merges meta keys into the hash" do
      ctx = described_class.new(current_domain: :billing, meta: { request_id: "xyz", actor_id: 42 })
      expect(ctx.to_h).to eq(current_domain: :billing, request_id: "xyz", actor_id: 42)
    end

    it "includes current_domain: nil when domain is blank" do
      ctx = described_class.new
      expect(ctx.to_h).to eq(current_domain: nil)
    end

    it "does not include meta keys when meta is empty" do
      ctx = described_class.new(current_domain: :identity)
      expect(ctx.to_h.keys).to eq([:current_domain])
    end

    it "does not let meta override current_domain" do
      ctx = described_class.new(
        current_domain: :billing,
        meta: { current_domain: :catalog, request_id: "x" }
      )
      expect(ctx.to_h).to eq(current_domain: :billing, request_id: "x")
    end

    it "produces a hash whose values are visible inside a service action" do
      ctx = described_class.new(current_domain: :catalog, meta: { request_id: "r1" })
      service_class = Class.new(Railsmith::BaseService) do
        def probe
          Railsmith::Result.success(
            value: { domain: current_domain, request_id: context[:request_id] }
          )
        end
      end

      result = service_class.call(action: :probe, params: {}, context: ctx.to_h)
      expect(result).to be_success
      expect(result.value).to eq({ domain: :catalog, request_id: "r1" })
    end
  end
end
