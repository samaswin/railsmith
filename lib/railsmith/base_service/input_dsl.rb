# frozen_string_literal: true

module Railsmith
  class BaseService
    # Adds the class-level `input` DSL to BaseService and its subclasses.
    #
    # Usage:
    #
    #   class UserService < Railsmith::BaseService
    #     model User
    #     domain :identity
    #
    #     input :email,    String,   required: true
    #     input :age,      Integer,  default: nil
    #     input :role,     String,   in: %w[admin member guest], default: "member"
    #     input :active,   :boolean, default: true
    #     input :metadata, Hash,     default: -> { {} }
    #   end
    #
    module InputDsl
      def self.included(base)
        base.extend(ClassMethods)
      end

      # Class-level DSL macros for declaring inputs on a service.
      module ClassMethods
        # Declare an input parameter.
        #
        # @param name     [Symbol, String]  parameter key
        # @param type     [Class, Symbol]   expected type; use :boolean for booleans
        # @param required [Boolean]         raises validation_error when missing (default: false)
        # @param default  [Object, #call]   static value or zero-arg lambda for the default
        # @param in       [Array, nil]      allowed values; other values produce validation_error
        # @param transform [Proc, nil]      applied after coercion; receives and returns the value
        def input(name, type, required: false, default: InputDefinition::UNSET, in: nil, transform: nil) # rubocop:disable Metrics/ParameterLists
          input_registry.register(
            InputDefinition.new(
              name, type,
              required: required,
              default: default,
              in: binding.local_variable_get(:in),
              transform: transform
            )
          )
        end

        # Returns the InputRegistry for this class.
        def input_registry
          @input_registry ||= InputRegistry.new
        end

        # Controls whether undeclared params are dropped after resolution.
        # Pass +false+ to disable filtering (opt-out).
        # Called with no argument returns the current setting.
        def filter_inputs(value = :__unset__)
          if value == :__unset__
            instance_variable_defined?(:@filter_inputs) ? @filter_inputs : true
          else
            @filter_inputs = value
          end
        end

        def inherited(subclass)
          super
          subclass.instance_variable_set(:@input_registry, input_registry.dup)
          # Propagate filter_inputs setting only if explicitly set on this class.
          return unless instance_variable_defined?(:@filter_inputs)

          subclass.instance_variable_set(:@filter_inputs, @filter_inputs)
        end
      end

      # Instance-level helper: run the resolver against the appropriate param slice.
      # Returns a Result. On success, updates @params in place with the resolved hash.
      # Called by BaseService#call before action dispatch when inputs are declared.
      def resolve_inputs
        registry = self.class.input_registry
        return Railsmith::Result.success(value: @params) unless registry.any?

        resolver = InputResolver.new(registry, filter: self.class.filter_inputs)

        # When a model is declared, inputs describe the attributes hash; otherwise raw params.
        if attributes_params?
          resolve_attribute_inputs(resolver)
        else
          resolve_raw_inputs(resolver)
        end
      end

      private

      def attributes_params?
        self.class.respond_to?(:model) && self.class.model &&
          @params.is_a?(Hash) && @params[:attributes].is_a?(Hash)
      end

      def resolve_attribute_inputs(resolver)
        result = resolver.resolve(@params[:attributes])
        return result if result.failure?

        @params = @params.merge(attributes: result.value)
        Railsmith::Result.success(value: @params)
      end

      def resolve_raw_inputs(resolver)
        result = resolver.resolve(@params.is_a?(Hash) ? @params : {})
        return result if result.failure?

        @params = result.value
        Railsmith::Result.success(value: @params)
      end
    end
  end
end
