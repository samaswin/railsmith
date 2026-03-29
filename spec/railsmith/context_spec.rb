# frozen_string_literal: true

require "spec_helper"

RSpec.describe Railsmith::Context do
  describe ".build" do
    it "returns a Context unchanged" do
      ctx = described_class.new(domain: :billing)
      expect(described_class.build(ctx)).to be(ctx)
    end

    it "returns a new Context with auto request_id for nil" do
      ctx = described_class.build(nil)
      expect(ctx).to be_a(described_class)
      expect(ctx.domain).to be_nil
      expect(ctx.request_id).to match(/\A[0-9a-f\-]{36}\z/)
    end

    it "returns a new Context with auto request_id for empty hash" do
      ctx = described_class.build({})
      expect(ctx).to be_a(described_class)
      expect(ctx.request_id).to match(/\A[0-9a-f\-]{36}\z/)
    end

    it "wraps a hash with :domain" do
      ctx = described_class.build({ domain: :catalog, actor_id: 7 })
      expect(ctx.domain).to eq(:catalog)
      expect(ctx[:actor_id]).to eq(7)
    end

    it "remaps :current_domain to :domain without a deprecation warning" do
      ctx = nil
      expect { ctx = described_class.build({ current_domain: :billing, request_id: "r1" }) }.not_to output.to_stderr
      expect(ctx.domain).to eq(:billing)
      expect(ctx.request_id).to eq("r1")
    end

    it "preserves all extra keys from the hash" do
      ctx = described_class.build({ domain: :payments, actor_id: 42, trace_id: "t1" })
      expect(ctx[:actor_id]).to eq(42)
      expect(ctx[:trace_id]).to eq("t1")
    end
  end

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

  describe ".current / .current=" do
    around { |ex| described_class.current = nil; ex.run; described_class.current = nil }

    it "returns nil when nothing has been set" do
      expect(described_class.current).to be_nil
    end

    it "stores and retrieves a Context on the current thread" do
      ctx = described_class.new(domain: :billing)
      described_class.current = ctx
      expect(described_class.current).to be(ctx)
    end
  end

  describe ".with" do
    around { |ex| described_class.current = nil; ex.run; described_class.current = nil }

    it "sets the current context for the duration of the block" do
      captured = nil
      described_class.with(domain: :web, actor_id: 1) { captured = described_class.current }
      expect(captured).to be_a(described_class)
      expect(captured.domain).to eq(:web)
      expect(captured[:actor_id]).to eq(1)
    end

    it "restores the previous context after the block" do
      described_class.current = nil
      described_class.with(domain: :web) {}
      expect(described_class.current).to be_nil
    end

    it "restores the previous context even when the block raises" do
      described_class.current = nil
      expect { described_class.with(domain: :web) { raise "boom" } }.to raise_error("boom")
      expect(described_class.current).to be_nil
    end

    it "supports nesting — inner block does not bleed into outer" do
      outer_ctx = described_class.new(domain: :outer)
      described_class.current = outer_ctx

      inner_captured = nil
      described_class.with(domain: :inner) { inner_captured = described_class.current }

      expect(inner_captured.domain).to eq(:inner)
      expect(described_class.current).to be(outer_ctx)
    end

    it "accepts an existing Context instance" do
      ctx = described_class.new(domain: :billing, request_id: "fixed")
      captured = nil
      described_class.with(ctx) { captured = described_class.current }
      expect(captured).to be(ctx)
    end
  end
end
