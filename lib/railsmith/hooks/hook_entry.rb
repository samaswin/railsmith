# frozen_string_literal: true

module Railsmith
  module Hooks
    # Immutable value object describing a single declared hook.
    #
    # A hook applies to one or more action symbols, has a type
    # (+:before+, +:after+, or +:around+), an optional +:if+/+:unless+
    # condition, an optional +:name+ for later +skip_hook+ targeting,
    # and an optional list of domain keys used by global hooks to scope
    # execution to matching service domains.
    class HookEntry
      VALID_TYPES = %i[before after around].freeze
      VALID_POLARITIES = %i[if unless].freeze

      attr_reader :type, :actions, :block, :condition, :polarity, :name, :only_domains

      def initialize(type:, actions:, block:, condition: nil, polarity: :if, name: nil, only_domains: nil)
        raise ArgumentError, "type must be one of #{VALID_TYPES.inspect}" unless VALID_TYPES.include?(type)
        raise ArgumentError, "polarity must be one of #{VALID_POLARITIES.inspect}" unless VALID_POLARITIES.include?(polarity)
        raise ArgumentError, "hook block is required" if block.nil?
        raise ArgumentError, "actions must be a non-empty Array" if actions.nil? || actions.empty?

        @type = type
        @actions = actions.map(&:to_sym).freeze
        @block = block
        @condition = condition
        @polarity = polarity
        @name = name ? name.to_sym : nil
        @only_domains = only_domains ? only_domains.map { |d| Context.normalize_current_domain(d) }.freeze : nil
        freeze
      end

      # True when this hook targets the given action symbol.
      def applies_to?(action)
        actions.include?(action.to_sym)
      end

      # True when the global hook's domain filter matches (or is absent).
      # Class-level hooks are not domain-filtered; this always returns true for them.
      def matches_domain?(domain_key)
        return true if only_domains.nil?

        only_domains.include?(Context.normalize_current_domain(domain_key))
      end

      # Evaluate the +if+/+unless+ condition (if any) against the given service instance.
      # Returns true when the hook should fire for this call.
      def applicable?(instance)
        return true if condition.nil?

        raw = evaluate_condition(instance)
        polarity == :if ? !!raw : !raw
      end

      private

      def evaluate_condition(instance)
        case condition
        when Symbol
          instance.send(condition)
        when Proc
          # Lambdas: receive the service instance as an argument.
          # Non-lambda procs: instance_exec in the service context.
          if condition.lambda?
            condition.call(instance)
          else
            instance.instance_exec(&condition)
          end
        else
          raise ArgumentError, "unsupported condition type: #{condition.class}"
        end
      end
    end
  end
end
