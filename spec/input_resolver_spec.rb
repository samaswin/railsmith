# frozen_string_literal: true

require "spec_helper"

RSpec.describe Railsmith::BaseService::InputResolver do
  # Convenience builder for an InputRegistry
  def registry_for(*definitions)
    reg = Railsmith::BaseService::InputRegistry.new
    definitions.each { |d| reg.register(d) }
    reg
  end

  def defn(name, type, **opts)
    Railsmith::BaseService::InputDefinition.new(name, type, **opts)
  end

  def resolve(registry, params, filter: true)
    described_class.new(registry, filter: filter).resolve(params)
  end

  # =========================================================================
  # Empty registry — passthrough
  # =========================================================================

  describe "empty registry" do
    it "returns params unchanged when no inputs are declared" do
      result = resolve(Railsmith::BaseService::InputRegistry.new, { foo: "bar" })
      expect(result).to be_success
      expect(result.value).to eq({ foo: "bar" })
    end
  end

  # =========================================================================
  # Defaults
  # =========================================================================

  describe "defaults" do
    it "applies static default for missing key" do
      reg = registry_for(defn(:role, String, default: "member"))
      result = resolve(reg, {})
      expect(result.value[:role]).to eq("member")
    end

    it "calls lambda default each time" do
      calls = 0
      lam = lambda {
        calls += 1
        "generated"
      }
      reg = registry_for(defn(:token, String, default: lam))

      resolve(reg, {})
      resolve(reg, {})
      expect(calls).to eq(2)
    end

    it "does not override an explicitly provided value with the default" do
      reg = registry_for(defn(:role, String, default: "member"))
      result = resolve(reg, { role: "admin" })
      expect(result.value[:role]).to eq("admin")
    end

    it "accepts nil as an explicit default" do
      reg = registry_for(defn(:age, Integer, default: nil))
      result = resolve(reg, {})
      expect(result).to be_success
      expect(result.value[:age]).to be_nil
    end
  end

  # =========================================================================
  # Type coercion
  # =========================================================================

  describe "type coercion" do
    it "coerces string to integer" do
      reg = registry_for(defn(:count, Integer))
      result = resolve(reg, { count: "10" })
      expect(result.value[:count]).to eq(10)
    end

    it "returns failure on coercion error" do
      reg = registry_for(defn(:count, Integer))
      result = resolve(reg, { count: "nope" })
      expect(result).to be_failure
      expect(result.code).to eq("validation_error")
      expect(result.error.details[:errors]).to have_key(:count)
    end

    it "skips coercion for nil values" do
      reg = registry_for(defn(:age, Integer, default: nil))
      result = resolve(reg, {})
      expect(result.value[:age]).to be_nil
    end
  end

  # =========================================================================
  # Required validation
  # =========================================================================

  describe "required validation" do
    it "fails when required input is missing" do
      reg = registry_for(defn(:email, String, required: true))
      result = resolve(reg, {})
      expect(result).to be_failure
      expect(result.error.details[:errors][:email]).to be_present
    end

    it "fails when required input is nil" do
      reg = registry_for(defn(:email, String, required: true))
      result = resolve(reg, { email: nil })
      expect(result).to be_failure
    end

    it "fails when required input is empty string" do
      reg = registry_for(defn(:email, String, required: true))
      result = resolve(reg, { email: "" })
      expect(result).to be_failure
    end

    it "succeeds when required input is provided" do
      reg = registry_for(defn(:email, String, required: true))
      result = resolve(reg, { email: "a@b.com" })
      expect(result).to be_success
    end

    it "collects multiple required-field errors" do
      reg = registry_for(
        defn(:email, String, required: true),
        defn(:name,  String, required: true)
      )
      result = resolve(reg, {})
      expect(result.error.details[:errors].keys).to contain_exactly(:email, :name)
    end
  end

  # =========================================================================
  # Allowed-values validation (in:)
  # =========================================================================

  describe "in: constraint" do
    let(:reg) { registry_for(defn(:role, String, in: %w[admin member guest], default: "member")) }

    it "passes for an allowed value" do
      result = resolve(reg, { role: "admin" })
      expect(result).to be_success
    end

    it "fails for a disallowed value" do
      result = resolve(reg, { role: "superuser" })
      expect(result).to be_failure
      expect(result.error.details[:errors][:role]).to include("must be one of")
    end

    it "passes when the field is nil (not present)" do
      # nil is not checked against in: — required check handles presence
      result = resolve(reg, {})
      expect(result).to be_success
      expect(result.value[:role]).to eq("member")
    end
  end

  # =========================================================================
  # Transform
  # =========================================================================

  describe "transform" do
    it "applies the transform proc after coercion" do
      reg = registry_for(defn(:code, String, transform: lambda(&:upcase)))
      result = resolve(reg, { code: "abc" })
      expect(result.value[:code]).to eq("ABC")
    end

    it "skips transform for nil values" do
      reg = registry_for(defn(:code, String, transform: lambda(&:upcase)))
      result = resolve(reg, { code: nil })
      expect(result.value[:code]).to be_nil
    end
  end

  # =========================================================================
  # Filtering
  # =========================================================================

  describe "filtering" do
    let(:reg) { registry_for(defn(:name, String), defn(:age, Integer)) }

    it "drops undeclared keys by default" do
      result = resolve(reg, { name: "Alice", age: "30", secret: "x" })
      expect(result.value.keys).to contain_exactly(:name, :age)
    end

    it "normalises keys to symbols" do
      result = resolve(reg, { "name" => "Alice", "age" => "25" })
      expect(result.value.keys).to contain_exactly(:name, :age)
    end

    it "preserves undeclared keys when filter: false" do
      result = resolve(reg, { name: "Alice", age: "30", extra: "y" }, filter: false)
      expect(result.value).to have_key(:extra)
    end
  end

  # =========================================================================
  # Pipeline ordering
  # =========================================================================

  describe "pipeline ordering" do
    it "applies default before coercion (default value is already correct type)" do
      reg = registry_for(defn(:count, Integer, default: 5))
      result = resolve(reg, {})
      expect(result.value[:count]).to eq(5)
    end

    it "coerces before required validation (so a default-filled value passes)" do
      reg = registry_for(defn(:count, Integer, required: true, default: "3"))
      result = resolve(reg, {})
      expect(result).to be_success
      expect(result.value[:count]).to eq(3)
    end

    it "stops after coercion failure and does not run validation" do
      reg = registry_for(
        defn(:count, Integer),
        defn(:name,  String, required: true)
      )
      # count coercion will fail; name missing would also fail, but we want one failure at a time
      result = resolve(reg, { count: "nope" })
      expect(result).to be_failure
      expect(result.error.message).to match(/coercion/i)
    end
  end

  # =========================================================================
  # String key inputs (params from controllers often have string keys)
  # =========================================================================

  describe "string key support" do
    it "resolves inputs declared as symbols when params use string keys" do
      reg = registry_for(defn(:email, String, required: true))
      result = resolve(reg, { "email" => "test@example.com" })
      expect(result).to be_success
      expect(result.value[:email]).to eq("test@example.com")
    end
  end
end
