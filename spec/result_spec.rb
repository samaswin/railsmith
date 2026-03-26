# frozen_string_literal: true

RSpec.describe Railsmith::Result do
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
end
