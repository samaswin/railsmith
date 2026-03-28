# frozen_string_literal: true

module Railsmith
  # Explicit, immutable value object for domain context propagation.
  # Build one per request and pass it as `context` into service/operation calls.
  #
  # Example:
  #   ctx = Railsmith::DomainContext.new(current_domain: :billing, meta: { request_id: "abc" })
  #   BillingService.call(action: :create, params: params, context: ctx.to_h)
  class DomainContext
    attr_reader :current_domain, :meta

    def self.normalize_current_domain(value)
      return nil if value.nil?
      return nil if value.is_a?(String) && value.strip.empty?
      return value if value.is_a?(Symbol)

      value.respond_to?(:to_sym) ? value.to_sym : value
    end

    def initialize(current_domain: nil, meta: {})
      @current_domain = self.class.normalize_current_domain(current_domain)
      @meta = (meta || {}).freeze
    end

    # Serializes to a plain hash suitable for passing into service context.
    # +current_domain+ is authoritative; meta cannot replace it.
    def to_h
      extras =
        if meta.empty?
          {}
        else
          meta.reject { |key, _| key == :current_domain || key == "current_domain" }
        end
      { current_domain: current_domain }.merge(extras)
    end

    # Returns true when no domain has been set (allowed in flexible mode).
    def blank_domain?
      current_domain.nil?
    end
  end
end
