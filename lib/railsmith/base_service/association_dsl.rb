# frozen_string_literal: true

module Railsmith
  class BaseService
    # Adds class-level `has_many`, `has_one`, and `belongs_to` DSL macros.
    #
    # Usage:
    #
    #   class OrderService < Railsmith::BaseService
    #     model Order
    #     domain :commerce
    #
    #     has_many   :line_items,       service: LineItemService, dependent: :destroy
    #     has_one    :shipping_address, service: AddressService
    #     belongs_to :customer,         service: CustomerService, optional: true
    #   end
    #
    module AssociationDsl
      def self.included(base)
        base.extend(ClassMethods)
      end

      # Class-level DSL macros for declaring associations on a service.
      module ClassMethods
        # Declare a has_many association.
        #
        # @param name        [Symbol]  association key (matches nested param key)
        # @param service     [Class]   service class for the associated records
        # @param foreign_key [Symbol]  explicit FK; inferred from parent model when omitted
        # @param dependent   [Symbol]  :destroy, :nullify, :restrict, or :ignore (default)
        # @param validate    [Boolean] validate nested records (default: true)
        def has_many(name, service:, foreign_key: nil, dependent: :ignore, validate: true) # rubocop:disable Naming/PredicatePrefix
          association_registry.register(
            AssociationDefinition.new(
              name, :has_many,
              service: service,
              foreign_key: foreign_key,
              dependent: dependent,
              validate: validate
            )
          )
        end

        # Declare a has_one association.
        #
        # @param name        [Symbol]  association key
        # @param service     [Class]   service class for the associated record
        # @param foreign_key [Symbol]  explicit FK; inferred from parent model when omitted
        # @param dependent   [Symbol]  :destroy, :nullify, :restrict, or :ignore (default)
        # @param validate    [Boolean] validate nested records (default: true)
        def has_one(name, service:, foreign_key: nil, dependent: :ignore, validate: true) # rubocop:disable Naming/PredicatePrefix
          association_registry.register(
            AssociationDefinition.new(
              name, :has_one,
              service: service,
              foreign_key: foreign_key,
              dependent: dependent,
              validate: validate
            )
          )
        end

        # Declare a belongs_to association.
        #
        # @param name        [Symbol]  association key
        # @param service     [Class]   service class for the parent record
        # @param foreign_key [Symbol]  explicit FK; inferred as "#{name}_id" when omitted
        # @param optional    [Boolean] skip presence validation (default: false)
        def belongs_to(name, service:, foreign_key: nil, optional: false)
          association_registry.register(
            AssociationDefinition.new(
              name, :belongs_to,
              service: service,
              foreign_key: foreign_key,
              optional: optional
            )
          )
        end

        # Returns the AssociationRegistry for this class.
        def association_registry
          @association_registry ||= AssociationRegistry.new
        end

        def inherited(subclass)
          super
          subclass.instance_variable_set(:@association_registry, association_registry.dup)
        end
      end
    end
  end
end
