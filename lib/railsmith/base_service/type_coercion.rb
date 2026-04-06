# frozen_string_literal: true

module Railsmith
  class BaseService
    # Handles automatic type conversion for declared inputs.
    #
    # Supported types and their coercion behaviour:
    #
    #   String     → value.to_s
    #   Integer    → Integer(value)   — strict; "abc" raises CoercionError
    #   Float      → Float(value)     — strict
    #   BigDecimal → BigDecimal(value.to_s)
    #   :boolean   → true/false; raises CoercionError for unrecognised values
    #   Date       → Date.parse(value.to_s)
    #   DateTime   → DateTime.parse(value.to_s)
    #   Time       → Time.parse(value.to_s)
    #   Symbol     → value.to_sym
    #   Array      → Array(value)     — wraps non-arrays
    #   Hash       → passthrough; raises CoercionError if not hash-like
    #
    # Custom coercions can be registered via Railsmith::Configuration:
    #
    #   Railsmith.configure do |c|
    #     c.register_coercion(:money, ->(v) { Money.new(v) })
    #   end
    #
    module TypeCoercion
      # Raised when a value cannot be coerced to the requested type.
      class CoercionError < StandardError
        attr_reader :field, :type

        def initialize(field, type, value)
          @field = field
          @type  = type
          super("Cannot coerce #{value.inspect} to #{type} for field '#{field}'")
        end
      end

      BUILTIN_COERCIONS = {
        String     => ->(v) { v.to_s },
        Integer    => ->(v) { Integer(v) },
        Float      => ->(v) { Float(v) },
        Symbol     => ->(v) { v.to_sym },
        Array      => ->(v) { Array(v) },
        Hash       => lambda { |v|
          raise TypeError, "expected Hash" unless v.is_a?(Hash)

          v
        },
        :boolean   => lambda { |v|
          return true  if [true,  "true",  "1", 1].include?(v)
          return false if [false, "false", "0", 0].include?(v)

          raise ArgumentError, "unrecognised boolean value"
        }
      }.freeze

      # Lazily-resolved coercions for types that may not be loaded at require time.
      LAZY_COERCIONS = {
        "Date"       => -> { ->(v) { Date.parse(v.to_s) } },
        "DateTime"   => -> { ->(v) { DateTime.parse(v.to_s) } },
        "Time"       => -> { ->(v) { Time.parse(v.to_s) } },
        "BigDecimal" => -> { ->(v) { BigDecimal(v.to_s) } }
      }.freeze

      class << self
        # Coerce +value+ to +type+ for the named +field+.
        # Returns +value+ unchanged when it is already the right type, or when
        # no coercion is defined for the type.
        # Returns +nil+ unchanged (callers handle required-nil separately).
        #
        # @raise [CoercionError] if coercion fails
        def coerce(field, value, type)
          return value if value.nil?
          return value if already_correct_type?(value, type)

          coercer = find_coercer(type)
          return value unless coercer

          coercer.call(value)
        rescue CoercionError
          raise
        rescue ArgumentError, TypeError, StandardError => e
          raise CoercionError.new(field, type, value)
        end

        private

        def already_correct_type?(value, type)
          case type
          when :boolean
            value == true || value == false
          when Class
            value.is_a?(type)
          else
            false
          end
        end

        def find_coercer(type)
          # 1. Check custom coercions registered via Configuration
          custom = Railsmith.configuration.custom_coercions[type]
          return custom if custom

          # 2. Built-in coercions keyed by Class or Symbol
          builtin = BUILTIN_COERCIONS[type]
          return builtin if builtin

          # 3. Lazy coercions keyed by type name string (Date, DateTime, Time, BigDecimal)
          type_name = type.respond_to?(:name) ? type.name : type.to_s
          lazy = LAZY_COERCIONS[type_name]
          lazy&.call
        end
      end
    end
  end
end
