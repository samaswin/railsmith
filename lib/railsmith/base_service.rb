# frozen_string_literal: true

module Railsmith
  # Base service entrypoint with explicit (non-hook) lifecycle.
  class BaseService
    require_relative "base_service/dup_helpers"
    require_relative "base_service/validation"
    require_relative "base_service/crud_actions"
    require_relative "base_service/bulk_params"
    require_relative "base_service/bulk_execution"
    require_relative "base_service/bulk_contract"
    require_relative "base_service/bulk_actions"
    require_relative "base_service/crud_model_resolution"
    require_relative "base_service/crud_record_helpers"
    require_relative "base_service/crud_error_mapping"
    require_relative "base_service/crud_transactions"
    include DupHelpers
    include Validation
    include CrudActions
    include BulkActions

    include CrudModelResolution
    include CrudRecordHelpers
    include CrudErrorMapping
    include CrudTransactions

    class << self
      def call(action:, params: {}, context: {})
        new(params:, context:).call(action:)
      end

      def model(model_class = nil)
        return @model_class if model_class.nil?

        @model_class = model_class
      end
    end

    attr_reader :params, :context

    def initialize(params:, context:)
      @params = deep_dup(params || {})
      @context = deep_dup(context || {})
    end

    def call(action:)
      normalized_action = normalize_action(action)
      return invalid_action_result(action: normalized_action) unless valid_action?(normalized_action)

      result = execute_action(action: normalized_action)
      normalize_result(result)
    end

    private

    def execute_action(action:)
      public_send(action)
    end

    def normalize_result(value)
      return value if value.is_a?(Result)

      Result.success(value:)
    end

    def valid_action?(action)
      action.is_a?(Symbol) && respond_to?(action, true)
    end

    def normalize_action(action)
      return action.to_sym if action.respond_to?(:to_sym)

      action
    end

    def invalid_action_result(action:)
      Result.failure(
        error: Errors.validation_error(
          message: "Invalid action",
          details: { action: action }
        )
      )
    end
  end
end
