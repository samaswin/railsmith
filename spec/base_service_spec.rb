# frozen_string_literal: true

require "spec_helper"

RSpec.describe Railsmith::BaseService do
  describe ".call" do
    it "allows subclass action override by defining a method" do
      service_class = Class.new(described_class) do
        def create
          Railsmith::Result.success(value: { created: true })
        end
      end

      result = service_class.call(action: :create, params: {}, context: {})
      expect(result).to be_success
      expect(result.value).to eq({ created: true })
    end

    it "returns failure result for invalid action" do
      service_class = Class.new(described_class)

      result = service_class.call(action: :nope, params: {}, context: {})

      expect(result).to be_failure
      expect(result.code).to eq("validation_error")
      expect(result.error.to_h).to include(code: "validation_error", message: "Invalid action")
      expect(result.error.to_h.fetch(:details)).to eq({ action: :nope })
    end

    it "passes through context but duplicates it to avoid mutation leaks" do
      context = { actor: { id: 123 }, flags: %w[a b] }

      service_class = Class.new(described_class) do
        def create
          context[:actor][:id] = 999
          context[:flags] << "c"
          Railsmith::Result.success(value: context)
        end
      end

      result = service_class.call(action: :create, params: {}, context: context)

      expect(result).to be_success
      expect(context).to eq({ actor: { id: 123 }, flags: %w[a b] })
      expect(result.value).to eq({ actor: { id: 999 }, flags: %w[a b c] })
    end

    it "treats non-Result action return values as success values" do
      service_class = Class.new(described_class) do
        def create
          { ok: true }
        end
      end

      result = service_class.call(action: :create, params: {}, context: {})
      expect(result).to be_success
      expect(result.value).to eq({ ok: true })
    end
  end

  describe "#validate" do
    it "returns success when required keys are present" do
      service = described_class.new(params: { email: "jane@doe.org" }, context: {})

      result = service.validate(service.params, required_keys: [:email])

      expect(result).to be_success
      expect(result.value).to eq({ email: "jane@doe.org" })
    end

    it "returns failure when required keys are missing" do
      service = described_class.new(params: {}, context: {})

      result = service.validate(service.params, required_keys: %i[email age])

      expect(result).to be_failure
      expect(result.code).to eq("validation_error")
      expect(result.error.to_h.fetch(:details)).to eq({ missing: %w[email age] })
    end

    it "supports a dry-validation-like contract object" do
      contract = Class.new do
        def initialize
          @validation_result_class = Struct.new(:ok, :errors) do
            def success?
              ok
            end
          end
        end

        def validation_result(success:, errors:)
          @validation_result_class.new(success, errors)
        end

        def call(input)
          return validation_result(success: true, errors: {}) if input[:email]

          validation_result(success: false, errors: { email: ["is missing"] })
        end
      end.new

      service = described_class.new(params: { email: nil }, context: {})

      result = service.validate(service.params, contract: contract)

      expect(result).to be_failure
      expect(result.error.to_h.fetch(:details)).to eq({ errors: { email: ["is missing"] } })
    end
  end
end
