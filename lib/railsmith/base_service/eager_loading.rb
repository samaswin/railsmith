# frozen_string_literal: true

module Railsmith
  class BaseService
    # Adds a class-level `includes` DSL macro for declaring eager loads.
    #
    # Declared includes are applied automatically in `find_record` (via
    # `base_scope`) and in the default `list` action.
    #
    # Usage:
    #
    #   class OrderService < Railsmith::BaseService
    #     model Order
    #     domain :commerce
    #
    #     includes :line_items, :customer
    #     includes line_items: [:product, :variant]   # multiple calls are additive
    #   end
    #
    module EagerLoading
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Declare one or more eager loads. Multiple calls are additive.
        #
        # Accepts the same arguments as ActiveRecord's `includes`:
        #   includes :foo, :bar
        #   includes foo: :bar
        #   includes foo: [:bar, :baz]
        def includes(*args)
          @eager_loads ||= []
          @eager_loads.concat(args)
        end

        # Returns the accumulated eager-load arguments for this class.
        def eager_loads
          @eager_loads || []
        end

        def inherited(subclass)
          super
          subclass.instance_variable_set(:@eager_loads, eager_loads.dup)
        end
      end

      private

      # Returns a scoped relation with eager loads applied if any are declared.
      # Falls back to the bare model class when no eager loads are configured.
      #
      # @param model_klass [Class]  the ActiveRecord model class
      # @return [ActiveRecord::Relation, Class]
      def base_scope(model_klass)
        loads = self.class.eager_loads
        return model_klass if loads.empty?

        model_klass.includes(*loads)
      end
    end
  end
end
