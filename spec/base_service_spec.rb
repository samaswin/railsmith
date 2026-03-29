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

    it "passes through context but isolates extras from the original to avoid mutation leaks" do
      original_context = { actor: { id: 123 }, flags: %w[a b] }

      service_class = Class.new(described_class) do
        def create
          # Nested objects in extras are mutable (deep-duped from original)
          context[:actor][:id] = 999
          context[:flags] << "c"
          Railsmith::Result.success(value: { actor: context[:actor], flags: context[:flags] })
        end
      end

      result = service_class.call(action: :create, params: {}, context: original_context)

      expect(result).to be_success
      expect(original_context).to eq({ actor: { id: 123 }, flags: %w[a b] })
      expect(result.value).to eq({ actor: { id: 999 }, flags: %w[a b c] })
    end

    context "thread-local context propagation" do
      probe_service = Class.new(Railsmith::BaseService) do
        def probe
          Railsmith::Result.success(value: { domain: context.domain, request_id: context.request_id })
        end
      end

      around { |ex| Railsmith::Context.current = nil; ex.run; Railsmith::Context.current = nil }

      it "uses the thread-local context when no context: arg is passed" do
        Railsmith::Context.with(domain: :web, request_id: "tl-1") do
          result = probe_service.call(action: :probe, params: {})
          expect(result.value).to eq({ domain: :web, request_id: "tl-1" })
        end
      end

      it "falls back to an auto-built context when no thread-local is set" do
        result = probe_service.call(action: :probe, params: {})
        expect(result.value[:domain]).to be_nil
        expect(result.value[:request_id]).to match(/\A[0-9a-f\-]{36}\z/)
      end

      it "gives explicit context: precedence over the thread-local context" do
        explicit = Railsmith::Context.new(domain: :explicit, request_id: "ex-1")
        Railsmith::Context.with(domain: :thread_local, request_id: "tl-2") do
          result = probe_service.call(action: :probe, params: {}, context: explicit)
          expect(result.value).to eq({ domain: :explicit, request_id: "ex-1" })
        end
      end

      it "gives explicit context: nil precedence over the thread-local context (builds empty context)" do
        Railsmith::Context.with(domain: :thread_local, request_id: "tl-3") do
          result = probe_service.call(action: :probe, params: {}, context: nil)
          expect(result.value[:domain]).to be_nil
          expect(result.value[:request_id]).not_to eq("tl-3")
        end
      end
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
