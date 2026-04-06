# frozen_string_literal: true

require "spec_helper"
require "bigdecimal"
require "date"

RSpec.describe Railsmith::BaseService::TypeCoercion do
  subject(:coerce) { described_class.method(:coerce) }

  def coerce(field, value, type)
    described_class.coerce(field, value, type)
  end

  # =========================================================================
  # nil passthrough
  # =========================================================================

  it "returns nil unchanged for any type" do
    expect(coerce(:x, nil, String)).to be_nil
    expect(coerce(:x, nil, Integer)).to be_nil
    expect(coerce(:x, nil, :boolean)).to be_nil
  end

  # =========================================================================
  # Already-correct-type passthrough
  # =========================================================================

  it "returns value unchanged when it is already the right type" do
    expect(coerce(:x, "hello", String)).to eq("hello")
    expect(coerce(:x, 42, Integer)).to eq(42)
    expect(coerce(:x, 3.14, Float)).to eq(3.14)
    expect(coerce(:x, :sym, Symbol)).to eq(:sym)
    expect(coerce(:x, [1, 2], Array)).to eq([1, 2])
    expect(coerce(:x, { a: 1 }, Hash)).to eq({ a: 1 })
    expect(coerce(:x, true, :boolean)).to be true
    expect(coerce(:x, false, :boolean)).to be false
  end

  # =========================================================================
  # String
  # =========================================================================

  describe "String coercion" do
    it "converts integer to string" do
      expect(coerce(:f, 42, String)).to eq("42")
    end

    it "converts symbol to string" do
      expect(coerce(:f, :hello, String)).to eq("hello")
    end
  end

  # =========================================================================
  # Integer
  # =========================================================================

  describe "Integer coercion" do
    it "converts numeric string" do
      expect(coerce(:f, "7", Integer)).to eq(7)
    end

    it "raises CoercionError for float string (strict coercion)" do
      expect { coerce(:f, "7.9", Integer) }
        .to raise_error(described_class::CoercionError)
    end

    it "raises CoercionError for non-numeric string" do
      expect { coerce(:f, "abc", Integer) }
        .to raise_error(described_class::CoercionError, /f/)
    end

    it "raises CoercionError for nil-like string" do
      expect { coerce(:f, "nil", Integer) }
        .to raise_error(described_class::CoercionError)
    end
  end

  # =========================================================================
  # Float
  # =========================================================================

  describe "Float coercion" do
    it "converts numeric string" do
      expect(coerce(:f, "3.14", Float)).to be_within(0.001).of(3.14)
    end

    it "raises CoercionError for non-numeric string" do
      expect { coerce(:f, "nope", Float) }
        .to raise_error(described_class::CoercionError)
    end
  end

  # =========================================================================
  # BigDecimal
  # =========================================================================

  describe "BigDecimal coercion" do
    it "converts a numeric string" do
      result = coerce(:price, "9.99", BigDecimal)
      expect(result).to be_a(BigDecimal)
      expect(result).to eq(BigDecimal("9.99"))
    end

    it "converts an integer" do
      result = coerce(:price, 5, BigDecimal)
      expect(result).to eq(BigDecimal("5"))
    end
  end

  # =========================================================================
  # :boolean
  # =========================================================================

  describe ":boolean coercion" do
    {
      "true"  => true,
      "1"     => true,
      1       => true,
      "false" => false,
      "0"     => false,
      0       => false
    }.each do |input, expected|
      it "coerces #{input.inspect} to #{expected}" do
        expect(coerce(:flag, input, :boolean)).to eq(expected)
      end
    end

    it "raises CoercionError for unrecognised value" do
      expect { coerce(:flag, "yes", :boolean) }
        .to raise_error(described_class::CoercionError, /flag/)
    end
  end

  # =========================================================================
  # Symbol
  # =========================================================================

  describe "Symbol coercion" do
    it "converts string to symbol" do
      expect(coerce(:f, "admin", Symbol)).to eq(:admin)
    end
  end

  # =========================================================================
  # Array
  # =========================================================================

  describe "Array coercion" do
    it "wraps a scalar in an array" do
      expect(coerce(:f, "item", Array)).to eq(["item"])
    end

    it "passes through an array" do
      expect(coerce(:f, [1, 2], Array)).to eq([1, 2])
    end
  end

  # =========================================================================
  # Hash
  # =========================================================================

  describe "Hash coercion" do
    it "passes through a hash" do
      expect(coerce(:f, { a: 1 }, Hash)).to eq({ a: 1 })
    end

    it "raises CoercionError for a non-hash" do
      expect { coerce(:f, "not_a_hash", Hash) }
        .to raise_error(described_class::CoercionError)
    end
  end

  # =========================================================================
  # Date / DateTime / Time
  # =========================================================================

  describe "Date coercion" do
    it "parses an ISO date string" do
      result = coerce(:dob, "2024-01-15", Date)
      expect(result).to eq(Date.new(2024, 1, 15))
    end

    it "raises CoercionError for invalid date string" do
      expect { coerce(:dob, "not-a-date", Date) }
        .to raise_error(described_class::CoercionError)
    end
  end

  describe "DateTime coercion" do
    it "parses an ISO datetime string" do
      result = coerce(:ts, "2024-01-15T10:00:00", DateTime)
      expect(result).to be_a(DateTime)
      expect(result.year).to eq(2024)
    end
  end

  describe "Time coercion" do
    it "parses a time string" do
      result = coerce(:ts, "2024-01-15 10:00:00", Time)
      expect(result).to be_a(Time)
    end
  end

  # =========================================================================
  # Unknown type — passthrough
  # =========================================================================

  describe "unknown type" do
    it "returns value unchanged when no coercion is defined" do
      custom_class = Class.new
      value = custom_class.new
      expect(coerce(:f, value, custom_class)).to be(value)
    end
  end

  # =========================================================================
  # Custom coercions via Configuration
  # =========================================================================

  describe "custom coercions" do
    around do |example|
      original = Railsmith.configuration.custom_coercions.dup
      example.run
      Railsmith.configuration.instance_variable_set(:@custom_coercions, original)
    end

    it "uses a registered custom coercion" do
      Railsmith.configure do |c|
        c.register_coercion(:upcase_string, ->(v) { v.to_s.upcase })
      end

      expect(coerce(:f, "hello", :upcase_string)).to eq("HELLO")
    end

    it "custom coercion takes precedence over built-in" do
      Railsmith.configure do |c|
        c.register_coercion(String, ->(v) { "CUSTOM:#{v}" })
      end

      expect(coerce(:f, 1, String)).to eq("CUSTOM:1")
    end
  end

  # =========================================================================
  # CoercionError carries field and type info
  # =========================================================================

  describe "CoercionError" do
    it "exposes field and type" do
      error = nil
      begin
        coerce(:email, "abc", Integer)
      rescue described_class::CoercionError => e
        error = e
      end

      expect(error).not_to be_nil
      expect(error.field).to eq(:email)
      expect(error.type).to eq(Integer)
      expect(error.message).to include("email")
    end
  end
end
