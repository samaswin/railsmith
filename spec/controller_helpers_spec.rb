# frozen_string_literal: true

require "spec_helper"

RSpec.describe Railsmith::ControllerHelpers do
  describe "ERROR_STATUS_MAP" do
    subject(:map) { described_class::ERROR_STATUS_MAP }

    it "maps validation_error to :unprocessable_entity" do
      expect(map["validation_error"]).to eq(:unprocessable_entity)
    end

    it "maps not_found to :not_found" do
      expect(map["not_found"]).to eq(:not_found)
    end

    it "maps conflict to :conflict" do
      expect(map["conflict"]).to eq(:conflict)
    end

    it "maps unauthorized to :unauthorized" do
      expect(map["unauthorized"]).to eq(:unauthorized)
    end

    it "maps unexpected to :internal_server_error" do
      expect(map["unexpected"]).to eq(:internal_server_error)
    end

    it "is frozen" do
      expect(map).to be_frozen
    end
  end

  describe "status resolution" do
    # Test the mapping logic in isolation without requiring a real Rails controller.
    def resolve_status(error_code)
      Railsmith::ControllerHelpers::ERROR_STATUS_MAP.fetch(
        error_code.to_s,
        :internal_server_error
      )
    end

    it "resolves known codes to their HTTP status" do
      expect(resolve_status("validation_error")).to eq(:unprocessable_entity)
      expect(resolve_status("not_found")).to eq(:not_found)
      expect(resolve_status("conflict")).to eq(:conflict)
      expect(resolve_status("unauthorized")).to eq(:unauthorized)
      expect(resolve_status("unexpected")).to eq(:internal_server_error)
    end

    it "defaults unknown codes to :internal_server_error" do
      expect(resolve_status("some_unknown_code")).to eq(:internal_server_error)
      expect(resolve_status("")).to eq(:internal_server_error)
    end
  end

  describe "Railsmith::Failure result serialization" do
    it "result.to_h includes success: false, error hash, and meta" do
      result = Railsmith::Result.failure(
        error: Railsmith::Errors.validation_error(
          message: "Name is blank",
          details: { name: ["can't be blank"] }
        )
      )
      exception = Railsmith::Failure.new(result)

      payload = exception.result.to_h
      expect(payload[:success]).to be false
      expect(payload[:error][:code]).to eq("validation_error")
      expect(payload[:error][:message]).to eq("Name is blank")
      expect(payload[:error][:details]).to eq({ name: ["can't be blank"] })
      expect(payload[:meta]).to eq({})
    end

    it "produces a valid payload for every mapped error code" do
      error_builders = {
        "validation_error" => -> { Railsmith::Errors.validation_error },
        "not_found"        => -> { Railsmith::Errors.not_found },
        "conflict"         => -> { Railsmith::Errors.conflict },
        "unauthorized"     => -> { Railsmith::Errors.unauthorized },
        "unexpected"       => -> { Railsmith::Errors.unexpected }
      }

      error_builders.each do |code, builder|
        result  = Railsmith::Result.failure(error: builder.call)
        payload = result.to_h
        expect(payload[:error][:code]).to eq(code), "expected code #{code}"
        status  = Railsmith::ControllerHelpers::ERROR_STATUS_MAP.fetch(code, :internal_server_error)
        expect(status).not_to be_nil
      end
    end
  end

  describe "module structure" do
    it "is a module" do
      expect(described_class).to be_a(Module)
    end

    it "defines ERROR_STATUS_MAP as a constant" do
      expect(described_class.const_defined?(:ERROR_STATUS_MAP)).to be true
    end
  end
end
