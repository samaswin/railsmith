# frozen_string_literal: true

module Railsmith
  module Hooks
    # Per-class (or global) store of declared hooks.
    #
    # The registry is the only mutable container in the hook system — the
    # internal HookChain is replaced wholesale on every change, preserving
    # immutability of previously-published chains. This matches the pattern
    # used by InputRegistry and AssociationRegistry.
    #
    # On class inheritance, BaseService calls #dup on the parent registry to
    # give the subclass its own copy, so declarations on the subclass do not
    # leak back upward. (See ADR-0002 for inheritance rules.)
    class HookRegistry
      def initialize(chain: HookChain.new)
        @chain = chain
      end

      # Append an entry, returning self for chaining.
      def add(entry)
        next_chain = @chain.append(entry)
        @chain = next_chain
        self
      end

      # Remove every entry with the given name (optionally restricted to a type).
      def remove(name:, type: nil)
        @chain = @chain.without(name, type: type)
        self
      end

      # The current chain (immutable snapshot).
      attr_reader :chain

      def entries
        @chain.entries
      end

      def empty?
        @chain.empty?
      end

      def any?
        !empty?
      end

      # Deep-dup: produce a new registry with the same (frozen) chain reference.
      # Chains are immutable, so sharing the frozen chain is safe; only the
      # registry wrapper needs its own identity for independent future growth.
      def dup
        self.class.new(chain: @chain)
      end
    end
  end
end
