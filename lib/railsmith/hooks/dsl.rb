# frozen_string_literal: true

module Railsmith
  module Hooks
    # Class-level DSL for declaring hooks on a BaseService subclass.
    #
    #   class OrderService < Railsmith::BaseService
    #     before :create do
    #       AuditLog.record(action: :create, actor: context[:actor_id])
    #     end
    #
    #     after :create do |result|
    #       EventBus.publish("order.created", result.value) if result.success?
    #     end
    #
    #     around :create do |action|
    #       Metrics.time("order.create") { action.call }
    #     end
    #   end
    #
    # Subclasses inherit all hooks from their parent (see ADR-0002). Named
    # hooks can be skipped via +skip_before+/+skip_after+/+skip_around+/+skip_hook+.
    module Dsl
      def self.included(base)
        base.extend(ClassMethods)
      end

      # Class-level macros installed on every BaseService subclass.
      module ClassMethods
        # Declare a +before+ hook on one or more actions. The block runs just
        # before the action method and is evaluated in the service instance
        # context (so +context+, +params+, and service helpers are available).
        #
        # @param actions [Array<Symbol>] one or more action symbols
        # @param if      [Symbol, Proc]  optional method name or callable guard
        # @param unless  [Symbol, Proc]  optional inverted guard
        # @param name    [Symbol]        optional name for +skip_before+ targeting
        def before(*actions, **options, &)
          register_hook(:before, actions, options, &)
        end

        # Declare an +after+ hook. The block receives the service's Result as
        # its block argument and runs after the action completes (successful
        # or not). After hooks cannot change the returned Result.
        def after(*actions, **options, &)
          register_hook(:after, actions, options, &)
        end

        # Declare an +around+ hook. The block receives a callable +action+;
        # it *must* invoke +action.call+ somewhere in its body or an
        # +AroundHookNotYieldedError+ is raised. Whatever the block returns
        # becomes the Result for the call, so around hooks can short-circuit
        # or transform the outcome.
        def around(*actions, **options, &)
          register_hook(:around, actions, options, &)
        end

        # Remove an inherited hook by name, regardless of type.
        # See ADR-0002 for why only named hooks can be skipped.
        def skip_hook(name)
          hook_registry.remove(name: name)
        end

        # Remove an inherited +before+ hook by name. Extra leading arguments
        # (typically action symbols) are accepted for documentation value and
        # ignored — the last symbol is the hook name.
        def skip_before(*args)
          hook_registry.remove(name: args.last, type: :before)
        end

        # Remove an inherited +after+ hook by name.
        def skip_after(*args)
          hook_registry.remove(name: args.last, type: :after)
        end

        # Remove an inherited +around+ hook by name.
        def skip_around(*args)
          hook_registry.remove(name: args.last, type: :around)
        end

        # Returns the HookRegistry for this class, creating it on first use.
        def hook_registry
          @hook_registry ||= HookRegistry.new
        end

        # Introspection helper: returns the effective HookChain for an action
        # on this class, including inherited entries but excluding global hooks
        # (global hooks are configuration, not part of the class itself).
        def hooks_for(action)
          hook_registry.chain.for_action(action)
        end

        # Propagate the parent registry into subclasses so child declarations
        # append to a private copy instead of mutating the parent's chain.
        def inherited(subclass)
          super
          subclass.instance_variable_set(:@hook_registry, hook_registry.dup)
        end

        private

        def register_hook(type, actions, options, &block)
          validate_hook_args!(actions, block)
          hook_registry.add(build_hook_entry(type, actions, options, block))
        end

        def validate_hook_args!(actions, block)
          raise ArgumentError, "hook block is required" if block.nil?
          raise ArgumentError, "at least one action symbol is required" if actions.empty?
        end

        def build_hook_entry(type, actions, options, block)
          condition, polarity = extract_condition(options)
          HookEntry.new(
            type: type,
            actions: actions,
            block: block,
            condition: condition,
            polarity: polarity,
            name: options[:name],
            only_domains: nil # domain filtering is global-only
          )
        end

        def extract_condition(options)
          if options.key?(:if) && options.key?(:unless)
            raise ArgumentError, "cannot declare both if: and unless: on the same hook"
          end

          if options.key?(:if)
            [options[:if], :if]
          elsif options.key?(:unless)
            [options[:unless], :unless]
          else
            [nil, :if]
          end
        end
      end

      # Instance-level entry point invoked by BaseService#execute_action.
      # Wraps the action dispatch in the full hook sandwich. When no hooks
      # are declared on the class or globally, this is effectively a no-op
      # cost — the Runner short-circuits on an empty chain.
      def run_lifecycle_hooks(action, &)
        Runner.new(instance: self, action: action).run(&)
      end
    end
  end
end
