# frozen_string_literal: true

module Railsmith
  class BaseService
    # Value object representing a single declared association on a service.
    #
    # Stores the association name, kind (:has_many, :has_one, :belongs_to),
    # the associated service class, and options governing cascading behaviour.
    class AssociationDefinition
      attr_reader :name, :kind, :service_class, :foreign_key, :dependent, :optional, :validate

      # @param name         [Symbol, String]  association key
      # @param kind         [Symbol]          :has_many, :has_one, or :belongs_to
      # @param service      [Class]           Railsmith::BaseService subclass for the associated records
      # @param options [Hash]            supported keys: :foreign_key, :dependent, :optional, :validate
      def initialize(name, kind, service:, **options)
        @name         = name.to_sym
        @kind         = kind.to_sym
        @service_class = service
        @foreign_key  = options[:foreign_key]&.to_sym
        @dependent    = (options.fetch(:dependent, :ignore) || :ignore).to_sym
        @optional     = options.fetch(:optional, false)
        @validate     = options.fetch(:validate, true)
        freeze
      end

      # Returns the FK column name (Symbol) for this association.
      # Falls back to auto-inference from the parent model class when no
      # explicit foreign_key was given.
      #
      # has_many / has_one: FK lives on the child → parent_model_id  (e.g. order_id)
      # belongs_to:         FK lives on this record → association_name_id (e.g. customer_id)
      #
      # @param parent_model_class [Class, nil]  the parent model class (used for inference)
      def inferred_foreign_key(parent_model_class = nil)
        return @foreign_key if @foreign_key

        case kind
        when :has_many, :has_one
          :"#{underscore_model_name(parent_model_class)}_id"
        when :belongs_to
          :"#{name}_id"
        end
      end

      private

      def underscore_model_name(model_class)
        return "" unless model_class

        model_name = model_class.name.to_s.split("::").last
        model_name
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .downcase
      end
    end
  end
end
