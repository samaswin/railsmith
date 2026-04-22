# frozen_string_literal: true

RSpec.describe Railsmith::Result do
  describe ".new" do
    it "is private — callers must use .success or .failure" do
      expect { described_class.new(success: true, value: nil, error: nil, meta: {}) }
        .to raise_error(NoMethodError)
    end
  end

  describe "immutability" do
    it "freezes the result object" do
      expect(described_class.success(value: :ok)).to be_frozen
    end

    it "freezes failure results" do
      expect(described_class.failure(code: :not_found, message: "Missing")).to be_frozen
    end

    it "freezes the embedded error payload" do
      result = described_class.failure(code: :conflict, message: "Oops")

      expect(result.error).to be_frozen
    end
  end

  describe ".success" do
    it "builds a success result with queries and accessors" do
      result = described_class.success(value: { id: 123 }, meta: { request_id: "abc" })

      expect(result.success?).to be(true)
      expect(result.failure?).to be(false)
      expect(result.value).to eq({ id: 123 })
      expect(result.error).to be_nil
      expect(result.code).to be_nil
      expect(result.meta).to eq({ request_id: "abc" })
    end

    it "defaults meta to empty hash" do
      result = described_class.success(value: :ok)

      expect(result.meta).to eq({})
    end

    it "serializes to a stable payload" do
      result = described_class.success(value: { ok: true }, meta: { trace_id: "t1" })

      expect(result.to_h).to eq(
        {
          success: true,
          value: { ok: true },
          meta: { trace_id: "t1" }
        }
      )

      expect(result.as_json).to eq(result.to_h)
    end
  end

  describe ".failure" do
    it "builds a failure result from code/message/details" do
      result = described_class.failure(
        code: :not_found,
        message: "User not found",
        details: { model: "User", id: 1 },
        meta: { request_id: "r1" }
      )

      expect(result.success?).to be(false)
      expect(result.failure?).to be(true)
      expect(result.value).to be_nil
      expect(result.error).not_to be_nil
      expect(result.code).to eq("not_found")
      expect(result.meta).to eq({ request_id: "r1" })

      expect(result.error.to_h).to eq(
        { code: "not_found", message: "User not found", details: { model: "User", id: 1 } }
      )
    end

    it "builds a failure result from a prebuilt error payload" do
      error = Railsmith::Errors.conflict(message: "Already exists", details: { key: "email" })
      result = described_class.failure(error:)

      expect(result.code).to eq("conflict")
      expect(result.error).to eq(error)
    end

    it "defaults meta to empty hash" do
      result = described_class.failure(code: :unauthorized, message: "Nope")

      expect(result.meta).to eq({})
    end

    it "serializes to a stable payload" do
      result = described_class.failure(
        code: :unauthorized,
        message: "Nope",
        details: { reason: "missing_token" },
        meta: { trace_id: "t2" }
      )

      expect(result.to_h).to eq(
        {
          success: false,
          error: { code: "unauthorized", message: "Nope", details: { reason: "missing_token" } },
          meta: { trace_id: "t2" }
        }
      )

      expect(result.as_json).to eq(result.to_h)
    end
  end

  describe "#and_then" do
    it "runs the block on success and returns the block's Result" do
      result = described_class.success(value: 10)
                              .and_then { |v| described_class.success(value: v * 2) }

      expect(result.success?).to be(true)
      expect(result.value).to eq(20)
    end

    it "skips the block on failure and returns self" do
      original = described_class.failure(code: :not_found, message: "Missing")
      ran = false
      returned = original.and_then do |_v|
        ran = true
        described_class.success(value: 1)
      end

      expect(ran).to be(false)
      expect(returned).to be(original)
    end

    it "propagates failure returned by the block" do
      result = described_class.success(value: 5)
                              .and_then do |_v|
        described_class.failure(
          code: :invalid, message: "Bad"
        )
      end

      expect(result.failure?).to be(true)
      expect(result.code).to eq("invalid")
    end

    it "preserves original meta in the chained result" do
      result = described_class.success(value: 1, meta: { trace_id: "t1" })
                              .and_then { |v| described_class.success(value: v + 1) }

      expect(result.meta).to include(trace_id: "t1")
    end

    it "lets chained result meta take precedence over original meta on key conflicts" do
      result = described_class.success(value: 1, meta: { trace_id: "original" })
                              .and_then do |v|
        described_class.success(
          value: v, meta: { trace_id: "chained" }
        )
      end

      expect(result.meta[:trace_id]).to eq("chained")
    end

    it "can be chained multiple times" do
      result = described_class.success(value: 1)
                              .and_then { |v| described_class.success(value: v + 1) }
                              .and_then { |v| described_class.success(value: v * 3) }

      expect(result.value).to eq(6)
    end

    it "short-circuits remaining chain on first failure" do
      ran = false
      first = described_class.success(value: 1)
                             .and_then { |_v| described_class.failure(code: :boom, message: "Boom") }
      result = first.and_then do |_v|
        ran = true
        described_class.success(value: 99)
      end

      expect(ran).to be(false)
      expect(result.failure?).to be(true)
      expect(result.code).to eq("boom")
    end
  end

  describe "#or_else" do
    it "runs the block on failure and returns the block's Result" do
      result = described_class.failure(code: :not_found, message: "Missing")
                              .or_else { |e| described_class.success(value: "recovered: #{e.message}") }

      expect(result.success?).to be(true)
      expect(result.value).to eq("recovered: Missing")
    end

    it "skips the block on success and returns self" do
      original = described_class.success(value: 42)
      ran = false
      returned = original.or_else do |_e|
        ran = true
        described_class.failure(code: :x, message: "x")
      end

      expect(ran).to be(false)
      expect(returned).to be(original)
    end

    it "can recover and continue an and_then chain" do
      result = described_class.failure(code: :transient, message: "Retry")
                              .or_else { |_e| described_class.success(value: "default") }
                              .and_then { |v| described_class.success(value: "#{v}!") }

      expect(result.value).to eq("default!")
    end

    it "preserves original meta in the recovered result" do
      result = described_class.failure(code: :err, message: "err", meta: { trace_id: "t2" })
                              .or_else { |_e| described_class.success(value: "ok") }

      expect(result.meta).to include(trace_id: "t2")
    end
  end

  describe "#on_success" do
    it "yields the value and returns self for a success result" do
      result = described_class.success(value: 7)
      yielded = nil
      returned = result.on_success { |v| yielded = v }

      expect(yielded).to eq(7)
      expect(returned).to be(result)
    end

    it "does not yield for a failure result and returns self" do
      result = described_class.failure(code: :err, message: "err")
      ran = false
      returned = result.on_success { ran = true }

      expect(ran).to be(false)
      expect(returned).to be(result)
    end

    it "can be chained after and_then for side effects" do
      logged = []
      described_class.success(value: 1)
                     .and_then { |v| described_class.success(value: v + 1) }
                     .on_success { |v| logged << v }

      expect(logged).to eq([2])
    end
  end

  describe "#on_failure" do
    it "yields the error and returns self for a failure result" do
      result = described_class.failure(code: :not_found, message: "Missing")
      yielded = nil
      returned = result.on_failure { |e| yielded = e }

      expect(yielded).to eq(result.error)
      expect(returned).to be(result)
    end

    it "does not yield for a success result and returns self" do
      result = described_class.success(value: 1)
      ran = false
      returned = result.on_failure { ran = true }

      expect(ran).to be(false)
      expect(returned).to be(result)
    end

    it "is usable as a logging tap in a chain" do
      errors = []
      described_class.success(value: 1)
                     .and_then { |_v| described_class.failure(code: :boom, message: "Boom") }
                     .on_failure { |e| errors << e.code }

      expect(errors).to eq(["boom"])
    end
  end
end
