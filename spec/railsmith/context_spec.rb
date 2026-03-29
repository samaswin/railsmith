# frozen_string_literal: true

require "spec_helper"

RSpec.describe Railsmith::Context do
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
    it "stores domain as a symbol" do
      ctx = described_class.new(domain: "billing")
      expect(ctx.domain).to eq(:billing)
    end

    it "accepts a symbol directly" do
      ctx = described_class.new(domain: :catalog)
      expect(ctx.domain).to eq(:catalog)
    end

    it "allows nil domain (flexible mode)" do
      ctx = described_class.new
      expect(ctx.domain).to be_nil
    end

    it "treats a blank string domain as nil" do
      expect(described_class.new(domain: "").domain).to be_nil
    end

    it "stores arbitrary extra kwargs at the top level" do
      ctx = described_class.new(domain: :billing, actor_id: 42, trace_id: "abc")
      expect(ctx[:actor_id]).to eq(42)
      expect(ctx[:trace_id]).to eq("abc")
    end

    it "accepts current_domain: as a deprecated alias for domain:" do
      expect { described_class.new(current_domain: :billing) }.to output(/deprecated/).to_stderr
    end

    it "uses current_domain: value when domain: is absent" do
      ctx = nil
      expect { ctx = described_class.new(current_domain: :billing) }.to output(/deprecated/).to_stderr
      expect(ctx.domain).to eq(:billing)
    end

    it "is frozen after construction" do
      ctx = described_class.new(domain: :billing)
      expect(ctx).to be_frozen
    end
  end

  describe "#request_id" do
    it "is auto-generated as a UUID when not provided" do
      ctx = described_class.new
      expect(ctx.request_id).to match(/\A[0-9a-f\-]{36}\z/)
    end

    it "is unique per instance" do
      expect(described_class.new.request_id).not_to eq(described_class.new.request_id)
    end

    it "uses the provided value when request_id is explicitly set" do
      ctx = described_class.new(request_id: "my-fixed-id")
      expect(ctx.request_id).to eq("my-fixed-id")
    end

    it "is accessible via []" do
      ctx = described_class.new(request_id: "r99")
      expect(ctx[:request_id]).to eq("r99")
    end
  end

  describe "#current_domain" do
    it "returns the same value as domain" do
      ctx = described_class.new(domain: :billing)
      expect(ctx.current_domain).to eq(:billing)
    end
  end

  describe "#[]" do
    it "accesses extra keys by symbol" do
      ctx = described_class.new(domain: :billing, actor_id: 99)
      expect(ctx[:actor_id]).to eq(99)
    end

    it "returns domain for :domain key" do
      ctx = described_class.new(domain: :billing)
      expect(ctx[:domain]).to eq(:billing)
    end

    it "returns domain for :current_domain key" do
      ctx = described_class.new(domain: :billing)
      expect(ctx[:current_domain]).to eq(:billing)
    end
  end

  describe "#blank_domain?" do
    it "returns true when domain is nil" do
      expect(described_class.new.blank_domain?).to be true
    end

    it "returns false when domain is set" do
      expect(described_class.new(domain: :billing).blank_domain?).to be false
    end
  end

  describe "#to_h" do
    it "includes current_domain for backward compatibility" do
      ctx = described_class.new(domain: :billing)
      expect(ctx.to_h).to include(current_domain: :billing)
    end

    it "includes extra keys at the top level" do
      ctx = described_class.new(domain: :billing, actor_id: 42, request_id: "r1")
      expect(ctx.to_h).to include(current_domain: :billing, actor_id: 42, request_id: "r1")
    end

    it "includes current_domain: nil when domain is blank" do
      ctx = described_class.new
      expect(ctx.to_h).to include(current_domain: nil)
      expect(ctx.to_h).to have_key(:request_id)
    end

    it "includes all arbitrary extra keys" do
      ctx = described_class.new(domain: :billing, trace_id: "xyz", tenant_id: 99)
      expect(ctx.to_h).to include(current_domain: :billing, trace_id: "xyz", tenant_id: 99)
      expect(ctx.to_h).to have_key(:request_id)
    end

    it "produces a hash whose values are visible inside a service action" do
      ctx = described_class.new(domain: :catalog, request_id: "r1")
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
