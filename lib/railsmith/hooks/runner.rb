# frozen_string_literal: true

module Railsmith
  module Hooks
    # Executes the hook chain around a service action.
    #
    # Construction merges the global hook chain (from Railsmith.configuration)
    # with the class-level chain on the service, filters by action and
    # applicability (+if:+/+unless:+, +only:+), then splits into
    # before / around / after phases.
    #
    # Hook blocks are evaluated with +instance_exec+ on the service instance
    # so the block body has access to +params+, +context+, etc. -- matching
    # the ergonomics developers expect from ActiveRecord-style callbacks.
    class Runner
      def initialize(instance:, action:, global_chain: nil)
        @instance = instance
        @action = action.to_sym
        @service_class = instance.class
        @global_chain = global_chain || Runner.global_chain
      end

      # Entry point: runs the hook chain, yielding to +action_block+ when the
      # innermost point of the sandwich is reached. Returns whatever the chain
      # ultimately produces -- normally the service's Result.
      def run(&action_block)
        resolved = resolve_chain
        return action_block.call if resolved.empty?

        befores = resolved.of_type(:before).entries
        arounds = resolved.of_type(:around).entries
        afters  = resolved.of_type(:after).entries

        run_befores(befores)
        result = run_arounds(arounds, &action_block)
        run_afters(afters, result)
        result
      end

      # Class-level convenience: the current global HookChain, pulled fresh
      # from configuration so tests can mutate it between calls.
      def self.global_chain
        Railsmith.configuration.global_hooks.chain
      end

      private

      attr_reader :instance, :action, :service_class

      def resolve_chain
        class_chain = service_class.respond_to?(:hook_registry) ? service_class.hook_registry.chain : HookChain.new
        # Global hooks with +only:+ filter by the *service* domain (the bounded
        # context declared on the class via `domain :commerce`), not the caller's
        # context domain. Hooks are a property of the service being invoked,
        # so service-declared domain is the natural grouping key.
        service_domain = service_class.respond_to?(:domain) ? service_class.domain : nil

        # Global hooks wrap class hooks (execution-order outermost = declared first),
        # so they come first in the combined chain.
        combined = HookChain.new.concat(@global_chain.for_domain(service_domain)).concat(class_chain)
        applicable = combined.for_action(action).entries.select { |e| e.applicable?(instance) }
        HookChain.new(applicable)
      end

      def run_befores(entries)
        entries.each do |entry|
          instance.instance_exec(instance.params, &entry.block)
        end
      end

      # Run after-hooks in reverse chain order so class-level hooks fire first
      # and global (outermost) hooks fire last — matching the "global wraps class"
      # sandwich model used for before-hooks and around-hooks.
      def run_afters(entries, result)
        entries.reverse_each do |entry|
          instance.instance_exec(result, &entry.block)
        end
      end

      # Build a nested chain of around hooks, from outermost (first declared)
      # to innermost. The innermost call is the wrapped +action_block+;
      # each outer wrapper receives a callable that represents the remainder
      # of the chain plus the action.
      def run_arounds(entries, &action_block)
        return action_block.call if entries.empty?

        inner = action_block
        entries.reverse_each do |entry|
          inner = build_around_wrapper(entry, inner)
        end
        inner.call
      end

      # Wrap +next_call+ with +entry+'s around block, returning a new callable.
      # Enforces that the block invokes the wrapped action -- otherwise raises
      # +AroundHookNotYieldedError+ to surface the "forgot to yield" bug class.
      def build_around_wrapper(entry, next_call)
        inst = instance
        action_name = @action
        lambda do
          called = false
          yield_to_action = lambda do
            called = true
            next_call.call
          end
          result = inst.instance_exec(yield_to_action, &entry.block)
          unless called
            raise AroundHookNotYieldedError.new(
              service: inst.class, action: action_name, hook_name: entry.name
            )
          end
          result
        end
      end
    end
  end
end
