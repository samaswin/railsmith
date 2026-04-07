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
      # @param foreign_key  [Symbol, nil]     explicit FK column; inferred when omitted
      # @param dependent    [Symbol]          :destroy, :nullify, :restrict, or :ignore (default)
      # @param optional     [Boolean]         belongs_to only — skip presence validation
      # @param validate     [Boolean]         validate nested records (default: true)
      def initialize(name, kind, service:, foreign_key: nil, dependent: :ignore, optional: false, validate: true)
        @name         = name.to_sym
        @kind         = kind.to_sym
        @service_class = service
        @foreign_key  = foreign_key ? foreign_key.to_sym : nil
        @dependent    = (dependent || :ignore).to_sym
        @optional     = optional
        @validate     = validate
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
          model_name = parent_model_class&.name.to_s.split("::").last
          model_name = model_name.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
                                 .gsub(/([a-z\d])([A-Z])/, '\1_\2')
                                 .downcase
          :"#{model_name}_id"
        when :belongs_to
          :"#{name}_id"
        end
      end
    end
  end
end
