# frozen_string_literal: true

module Railsmith
  class BaseService
    # Exposes the current domain from context and emits instrumentation events
    # so domain tags flow into observability tooling on every service call.
    # @api private
    module DomainContextPropagation
      # Returns the domain key from the service context, or nil when not set.
      # A nil domain is permitted in flexible mode.
      def current_domain
        DomainContext.normalize_current_domain(context[:current_domain])
      end

      private

      # Wraps action execution with a domain-tagged instrumentation event.
      def execute_action(action:)
        Railsmith::CrossDomainGuard.emit_if_violation(instance: self, action: action)
        Instrumentation.instrument(
          "service.call",
          service: self.class.name,
          action: action,
          domain: current_domain
        ) { super }
      end
    end
  end
end
