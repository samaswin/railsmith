# frozen_string_literal: true

module Railsmith
  class BaseService
    # Holds all InputDefinition objects declared on a service class.
    # Supports inheritance via #dup — subclasses get their own copy that
    # can be extended without affecting the parent.
    class InputRegistry
      def initialize
        @definitions = {}
      end

      # Register an InputDefinition. Later registrations with the same name
      # overwrite earlier ones (allows subclass override).
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

      # Returns a new InputRegistry with shallow copies of all definitions.
      # InputDefinition objects are frozen so sharing them across classes is safe.
      def dup
        copy = self.class.new
        @definitions.each_value { |d| copy.register(d) }
        copy
      end
    end
  end
end
