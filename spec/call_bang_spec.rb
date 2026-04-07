# frozen_string_literal: true

require "spec_helper"

RSpec.describe "BaseService.call!" do
  let(:success_service) do
    Class.new(Railsmith::BaseService) do
      def fetch
        Railsmith::Result.success(value: { fetched: true })
      end
    end
  end

  let(:failure_service) do
    Class.new(Railsmith::BaseService) do
      def fetch
        Railsmith::Result.failure(
          error: Railsmith::Errors.validation_error(message: "Invalid input", details: { field: "email" })
        )
      end
    end
  end

  let(:not_found_service) do
    Class.new(Railsmith::BaseService) do
      def fetch
        Railsmith::Result.failure(error: Railsmith::Errors.not_found(message: "Record missing"))
      end
    end
  end

  describe "on success" do
    it "returns the result without raising" do
      result = success_service.call!(action: :fetch, params: {}, context: {})
      expect(result).to be_success
      expect(result.value).to eq({ fetched: true })
    end
  end

  describe "on failure" do
    it "raises Railsmith::Failure" do
      expect do
        failure_service.call!(action: :fetch, params: {}, context: {})
      end.to raise_error(Railsmith::Failure)
    end

    it "exception message matches the error message" do
      failure_service.call!(action: :fetch, params: {}, context: {})
    rescue Railsmith::Failure => e
      expect(e.message).to eq("Invalid input")
    end

    it "exception carries the original result" do
      failure_service.call!(action: :fetch, params: {}, context: {})
    rescue Railsmith::Failure => e
      expect(e.result).to be_a(Railsmith::Result)
      expect(e.result).to be_failure
    end

    it "exception delegates #code to the result" do
      failure_service.call!(action: :fetch, params: {}, context: {})
    rescue Railsmith::Failure => e
      expect(e.code).to eq("validation_error")
    end

    it "exception delegates #error to the result" do
      failure_service.call!(action: :fetch, params: {}, context: {})
    rescue Railsmith::Failure => e
      expect(e.error).to be_a(Railsmith::Errors::ErrorPayload)
      expect(e.error.details).to eq({ field: "email" })
    end

    it "exception delegates #meta to the result" do
      failure_service.call!(action: :fetch, params: {}, context: {})
    rescue Railsmith::Failure => e
      expect(e.meta).to eq({})
    end

    it "is a StandardError subclass" do
      expect(Railsmith::Failure.ancestors).to include(StandardError)
    end

    it "works with different error codes" do
      not_found_service.call!(action: :fetch, params: {}, context: {})
    rescue Railsmith::Failure => e
      expect(e.code).to eq("not_found")
      expect(e.message).to eq("Record missing")
    end
  end

  describe "invalid action" do
    it "raises Railsmith::Failure for an invalid action (call returns failure)" do
      blk = -> { success_service.call!(action: :nonexistent, params: {}, context: {}) }
      expect(&blk).to raise_error(Railsmith::Failure) { |e| expect(e.code).to eq("validation_error") }
    end
  end

  describe "Railsmith::Failure exception class" do
    it "can be rescued by StandardError" do
      rescued = false
      begin
        failure_service.call!(action: :fetch, params: {}, context: {})
      rescue StandardError
        rescued = true
      end
      expect(rescued).to be true
    end

    it "is not a RuntimeError subclass" do
      expect(Railsmith::Failure.ancestors).not_to include(RuntimeError)
    end
  end
end
