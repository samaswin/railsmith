# frozen_string_literal: true

module Railsmith
  class BaseService
    # Orchestrates the full input-processing pipeline for a single service call:
    #
    #   Raw params
    #     → Apply defaults       (fill missing keys with declared defaults)
    #     → Coerce types         (String → Integer, etc.)
    #     → Validate required    (missing required fields → validation_error)
    #     → Validate allowed     (in: constraint violations → validation_error)
    #     → Apply transforms     (optional post-coercion Proc)
    #     → Filter undeclared    (drop keys not declared as inputs, when filtering is on)
    #     → Return resolved hash or Result.failure
    #
    class InputResolver
      # @param registry [InputRegistry] the input definitions for this service
      # @param filter   [Boolean]       whether to drop undeclared keys (default: true)
      def initialize(registry, filter: true)
        @registry = registry
        @filter   = filter
      end

      # Run the pipeline against +raw_params+.
      #
      # @param raw_params [Hash]
      # @return [Railsmith::Result] success with resolved hash, or failure with validation_error
      def resolve(raw_params)
        return Result.success(value: raw_params) unless @registry.any?

        input = extract(raw_params)
        input = apply_defaults(input)

        coerce_result = coerce_types(input)
        return coerce_result if coerce_result.failure?

        input = coerce_result.value

        validate_result = validate(input)
        return validate_result if validate_result.failure?

        input = validate_result.value
        input = apply_transforms(input)
        input = filter_keys(input) if @filter

        Result.success(value: input)
      end

      private

      def extract(raw_params)
        raw_params.is_a?(Hash) ? raw_params.dup : {}
      end

      def apply_defaults(input)
        @registry.all.each_with_object(input) do |defn, result|
          next if result.key?(defn.name) || result.key?(defn.name.to_s)
          next unless defn.has_default?

          result[defn.name] = defn.resolve_default
        end
      end

      def coerce_types(input)
        errors  = {}
        coerced = {}

        # Preserve non-declared keys (they'll be filtered later if needed)
        input.each { |k, v| coerced[k] = v }

        @registry.all.each do |defn|
          value = fetch_value(input, defn.name)
          next if value.nil?

          begin
            coerced[defn.name] = TypeCoercion.coerce(defn.name, value, defn.type)
          rescue TypeCoercion::CoercionError => e
            errors[defn.name] = e.message
          end
        end

        return Result.success(value: coerced) if errors.empty?

        Result.failure(
          error: Errors.validation_error(
            message: "Type coercion failed",
            details: { errors: errors }
          )
        )
      end

      def validate(input)
        errors = {}

        @registry.all.each do |defn|
          value = fetch_value(input, defn.name)

          if defn.required && blank?(value)
            errors[defn.name] = "is required"
          elsif !value.nil? && defn.in_values && !defn.in_values.include?(value)
            errors[defn.name] = "must be one of: #{defn.in_values.join(", ")}"
          end
        end

        return Result.success(value: input) if errors.empty?

        Result.failure(
          error: Errors.validation_error(
            message: "Validation failed",
            details: { errors: errors }
          )
        )
      end

      def apply_transforms(input)
        @registry.all.each_with_object(input.dup) do |defn, result|
          next unless defn.transform

          value = fetch_value(result, defn.name)
          next if value.nil?

          result[defn.name] = defn.transform.call(value)
        end
      end

      def filter_keys(input)
        allowed = @registry.all.map(&:name).to_set
        input.each_with_object({}) do |(k, v), filtered|
          sym = k.to_sym
          filtered[sym] = v if allowed.include?(sym)
        end
      end

      # Fetch a value from the input hash accepting both symbol and string keys.
      def fetch_value(hash, name)
        hash.key?(name) ? hash[name] : hash[name.to_s]
      end

      def blank?(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end
    end
  end
end
