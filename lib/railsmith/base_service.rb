# frozen_string_literal: true

module Railsmith
  # Base service entrypoint with explicit (non-hook) lifecycle.
  class BaseService # rubocop:disable Metrics/ClassLength
    require_relative "base_service/dup_helpers"
    require_relative "base_service/validation"
    require_relative "base_service/input_definition"
    require_relative "base_service/input_registry"
    require_relative "base_service/type_coercion"
    require_relative "base_service/input_resolver"
    require_relative "base_service/input_dsl"
    require_relative "base_service/association_definition"
    require_relative "base_service/association_registry"
    require_relative "base_service/association_dsl"
    require_relative "base_service/eager_loading"
    require_relative "base_service/nested_writer"
    require_relative "base_service/crud_actions"
    require_relative "base_service/bulk_params"
    require_relative "base_service/bulk_execution"
    require_relative "base_service/bulk_contract"
    require_relative "base_service/bulk_actions"
    require_relative "base_service/crud_model_resolution"
    require_relative "base_service/crud_record_helpers"
    require_relative "base_service/crud_error_mapping"
    require_relative "base_service/crud_transactions"
    require_relative "base_service/context_propagation"
    include DupHelpers
    include Validation
    include InputDsl
    include AssociationDsl
    include EagerLoading
    include NestedWriter
    include CrudActions
    include BulkActions
    prepend ContextPropagation

    include CrudModelResolution
    include CrudRecordHelpers
    include CrudErrorMapping
    include CrudTransactions

    # Sentinel used to distinguish "context not passed" from "context: nil".
    UNSET_CONTEXT = Object.new.freeze
    private_constant :UNSET_CONTEXT

    class << self
      def call(action:, params: {}, context: UNSET_CONTEXT)
        resolved =
          if context.equal?(UNSET_CONTEXT)
            Context.current || Context.build(nil)
          else
            Context.build(context)
          end
        new(params:, context: resolved).call(action:)
      end

      def call!(action:, params: {}, context: UNSET_CONTEXT)
        result = call(action: action, params: params, context: context)
        raise Railsmith::Failure, result if result.failure?

        result
      end

      def model(model_class = nil)
        return @model_class if model_class.nil?

        @model_class = model_class
      end

      # Bounded-context key for this service (optional). When set, mismatches
      # against +context[:current_domain]+ emit warn-only instrumentation unless
      # the pair is listed in +Railsmith.configuration.cross_domain_allowlist+.
      def domain(domain_key = nil)
        return @service_domain if domain_key.nil?

        @service_domain = Context.normalize_current_domain(domain_key)
      end

      # @deprecated Use {.domain} instead.
      def service_domain(domain_key = nil)
        if domain_key.nil?
          warn "[DEPRECATION] `service_domain` reader is deprecated. Use `domain` instead."
        else
          warn "[DEPRECATION] `service_domain :#{domain_key}` is deprecated. Use `domain :#{domain_key}` instead."
        end
        domain(domain_key)
      end
    end

    attr_reader :params, :context

    def initialize(params:, context:)
      @params = deep_dup(params || {})
      @context = context.is_a?(Context) ? context : Context.build(context)
    end

    def call(action:)
      normalized_action = normalize_action(action)
      return invalid_action_result(action: normalized_action) unless valid_action?(normalized_action)

      if self.class.input_registry.any?
        input_result = resolve_inputs
        return input_result if input_result.failure?
      end

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
