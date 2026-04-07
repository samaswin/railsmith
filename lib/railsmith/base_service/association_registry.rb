# frozen_string_literal: true

module Railsmith
  class BaseService
    # Holds all AssociationDefinition objects declared on a service class.
    # Supports inheritance via #dup — subclasses get their own copy that can
    # be extended without affecting the parent.
    class AssociationRegistry
      def initialize
        @definitions = {}
      end

      # Register an AssociationDefinition. Later registrations with the same
      # name overwrite earlier ones (allows subclass override).
      def register(definition)
        @definitions[definition.name] = definition
        self
      end

      # All registered definitions in declaration order.
      def all
        @definitions.values
      end

      def [](name)
        @definitions[name.to_sym]
      end

      def any?
        @definitions.any?
      end

      def empty?
        @definitions.empty?
      end

      # Returns a new AssociationRegistry with the same definitions.
      # AssociationDefinition objects are frozen so sharing them is safe.
      def dup
        copy = self.class.new
        @definitions.each_value { |d| copy.register(d) }
        copy
      end
    end
  end
end
