# frozen_string_literal: true

module Railsmith
  module Hooks
    # Immutable, ordered list of HookEntry records. Chains are cheap value
    # objects: every "mutation" (append, filter, remove) returns a new chain,
    # which is how class-level registries stay safe to share across requests.
    class HookChain
      include Enumerable

      attr_reader :entries

      def initialize(entries = [])
        @entries = entries.dup.freeze
        freeze
      end

      def each(&)
        @entries.each(&)
      end

      def empty?
        @entries.empty?
      end

      def size
        @entries.size
      end

      # Returns a new chain containing only entries that target +action+.
      def for_action(action)
        action_sym = action.to_sym
        self.class.new(@entries.select { |e| e.applies_to?(action_sym) })
      end

      # Returns a new chain containing only entries of +type+ (:before/:after/:around).
      def of_type(type)
        self.class.new(@entries.select { |e| e.type == type })
      end

      # Returns a new chain filtered to entries whose domain scope matches +domain_key+.
      # Entries without a domain scope (class-level hooks) always pass.
      def for_domain(domain_key)
        self.class.new(@entries.select { |e| e.matches_domain?(domain_key) })
      end

      # Returns a new chain with every entry named +hook_name+ removed.
      # Optionally restrict removal to a specific hook type.
      def without(hook_name, type: nil)
        target = hook_name.to_sym
        self.class.new(@entries.reject { |e| e.name == target && (type.nil? || e.type == type) })
      end

      # Returns a new chain with +entry+ appended.
      def append(entry)
        self.class.new([*@entries, entry])
      end

      # Returns a new chain with every entry from +other+ appended, preserving order.
      # Self's entries come first (used for "global hooks wrap class hooks" layering
      # when called with global as the outer and class as the argument, or vice versa).
      def concat(other)
        return self if other.nil? || other.empty?

        self.class.new([*@entries, *other.entries])
      end
    end
  end
end
