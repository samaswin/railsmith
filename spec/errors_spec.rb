# frozen_string_literal: true

RSpec.describe Railsmith::Errors do
  describe ".validation_error" do
    it "returns normalized payload" do
      error = described_class.validation_error(details: { email: ["is invalid"] })

      expect(error.to_h).to eq(
        { code: "validation_error", message: "Validation failed", details: { email: ["is invalid"] } }
      )
    end

    it "defaults details to empty hash" do
      error = described_class.validation_error

      expect(error.to_h).to eq(
        { code: "validation_error", message: "Validation failed", details: {} }
      )
    end
  end

  describe ".not_found" do
    it "returns normalized payload" do
      error = described_class.not_found(message: "Record missing", details: { model: "User", id: 1 })

      expect(error.to_h).to eq(
        { code: "not_found", message: "Record missing", details: { model: "User", id: 1 } }
      )
    end
  end

  describe ".conflict" do
    it "returns normalized payload" do
      error = described_class.conflict(details: { field: "email" })

      expect(error.to_h).to eq(
        { code: "conflict", message: "Conflict", details: { field: "email" } }
      )
    end
  end

  describe ".unauthorized" do
    it "returns normalized payload" do
      error = described_class.unauthorized(message: "Access denied", details: { scope: "admin" })

      expect(error.to_h).to eq(
        { code: "unauthorized", message: "Access denied", details: { scope: "admin" } }
      )
    end
  end

  describe ".unexpected" do
    it "returns normalized payload and omits details when nil" do
      error = described_class.unexpected

      expect(error.to_h).to eq(
        { code: "unexpected", message: "Unexpected error" }
      )
    end

    it "includes details when present" do
      error = described_class.unexpected(details: { exception_class: "RuntimeError" })

      expect(error.to_h).to eq(
        { code: "unexpected", message: "Unexpected error", details: { exception_class: "RuntimeError" } }
      )
    end
  end

  describe Railsmith::Errors::ErrorPayload do
    it "coerces code/message to strings" do
      error = described_class.new(code: :not_found, message: :Nope, details: { a: 1 })

      expect(error.code).to eq("not_found")
      expect(error.message).to eq("Nope")
    end
  end
end
