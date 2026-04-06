# frozen_string_literal: true

module Railsmith
  class BaseService
    # Parameter validation helpers for service actions.
    module Validation
      # Explicit validation helper intended to be called from action methods.
      #
      # Supports either:
      # - required_keys: simple presence checks on Hash-like params
      #   (DEPRECATED — use the `input` DSL with `required: true` instead)
      # - contract: a dry-validation-like contract responding to `call(input)` and returning
      #   an object that responds to `success?` and `errors`
      def validate(input = params, required_keys: [], contract: nil)
        if required_keys.any? && self.class.input_registry.any?
          warn "[DEPRECATION] `required_keys:` on `validate()` is deprecated and ignored " \
               "when the `input` DSL is in use. Declare required inputs with " \
               "`input :#{required_keys.first}, ..., required: true` instead."
        elsif required_keys.any?
          warn "[DEPRECATION] `required_keys:` on `validate()` is deprecated. " \
               "Use the `input` DSL with `required: true` instead."
        end
        return validate_with_contract(contract, input) if contract

        validate_required_keys(input, required_keys)
      end

      private

      def validate_required_keys(input, required_keys)
        hash = input.is_a?(Hash) ? input : {}
        missing = required_keys.reject { |key| present_value?(hash[key]) }

        return Result.success(value: hash) if missing.empty?

        Result.failure(
          error: Errors.validation_error(
            message: "Validation failed",
            details: { missing: missing.map(&:to_s) }
          )
        )
      end

      def validate_with_contract(contract, input)
        result = contract.call(input)
        return Result.success(value: input) if contract_success?(result)

        Result.failure(
          error: Errors.validation_error(
            message: "Validation failed",
            details: { errors: contract_errors(result) }
          )
        )
      rescue StandardError => e
        Result.failure(error: Errors.unexpected(message: e.message))
      end

      def contract_success?(result)
        result.respond_to?(:success?) && result.success?
      end

      def contract_errors(result)
        return result.errors if result.respond_to?(:errors)

        { base: ["Invalid contract result"] }
      end

      def present_value?(value)
        return false if value.nil?
        return false if value.respond_to?(:empty?) && value.empty?

        true
      end
    end
  end
end
