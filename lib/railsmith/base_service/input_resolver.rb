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
    #
    module InputResolverHelpers
      private

      def type_coercion_failure(errors)
        Result.failure(
          error: Errors.validation_error(
            message: "Type coercion failed",
            details: { errors: errors }
          )
        )
      end

      def validation_failure(errors)
        Result.failure(
          error: Errors.validation_error(
            message: "Validation failed",
            details: { errors: errors }
          )
        )
      end

      def fetch_value(hash, name)
        hash.key?(name) ? hash[name] : hash[name.to_s]
      end

      def blank?(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end
    end

    # Resolves and validates declared service inputs.
    class InputResolver
      include InputResolverHelpers

      # @param registry [InputRegistry] the input definitions for this service
      # @param filter   [Boolean]       whether to drop undeclared keys (default: true)
      def initialize(registry, filter: true)
        @registry = registry
        @filter   = filter
      end

      # Run the pipeline against +raw_params+.
      #
      # @return [Railsmith::Result] success with resolved hash, or failure with validation_error
      def resolve(raw_params)
        return Result.success(value: raw_params) unless @registry.any?

        run_pipeline(extract(raw_params))
      end

      private

      def run_pipeline(input)
        input_with_defaults = apply_defaults(input)
        coerce_result = coerce_types(input_with_defaults)
        return coerce_result if coerce_result.failure?

        validate_result = validate(coerce_result.value)
        return validate_result if validate_result.failure?

        resolved = apply_transforms(validate_result.value)
        resolved = filter_keys(resolved) if @filter
        Result.success(value: resolved)
      end

      def extract(raw_params)
        raw_params.is_a?(Hash) ? raw_params.dup : {}
      end

      def apply_defaults(input)
        @registry.all.each_with_object(input) do |defn, result|
          next if result.key?(defn.name) || result.key?(defn.name.to_s)
          next unless defn.default?

          result[defn.name] = defn.resolve_default
        end
      end

      def coerce_types(input)
        errors = {}
        coerced = input.dup

        @registry.all.each do |defn|
          coerce_one(defn, input, coerced, errors)
        end

        return Result.success(value: coerced) if errors.empty?

        type_coercion_failure(errors)
      end

      def coerce_one(defn, input, coerced, errors)
        value = fetch_value(input, defn.name)
        return if value.nil?

        coerced[defn.name] = TypeCoercion.coerce(defn.name, value, defn.type)
      rescue TypeCoercion::CoercionError => e
        errors[defn.name] = e.message
      end

      def validate(input)
        errors = {}

        @registry.all.each do |defn|
          validate_one(defn, input, errors)
        end

        return Result.success(value: input) if errors.empty?

        validation_failure(errors)
      end

      def validate_one(defn, input, errors)
        value = fetch_value(input, defn.name)
        if defn.required && blank?(value)
          errors[defn.name] = "is required"
          return
        end

        allowed_values = defn.in_values
        return if value.nil? || allowed_values.nil? || allowed_values.include?(value)

        errors[defn.name] = "must be one of: #{allowed_values.join(", ")}"
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
        allowed = @registry.all.to_set(&:name)
        input.each_with_object({}) do |(k, v), filtered|
          sym = k.to_sym
          filtered[sym] = v if allowed.include?(sym)
        end
      end
    end
  end
end
