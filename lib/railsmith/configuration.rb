# frozen_string_literal: true

module Railsmith
  # Stores global settings used by gem components.
  class Configuration
    attr_accessor :warn_on_cross_domain_calls, :strict_mode,
                  :cross_domain_allowlist, :on_cross_domain_violation,
                  :fail_on_arch_violations

    def initialize
      @warn_on_cross_domain_calls = true
      @strict_mode = false
      @cross_domain_allowlist = []
      @on_cross_domain_violation = nil
      @fail_on_arch_violations = false
      @custom_coercions = {}
    end

    # Register a custom type coercion used by the input DSL.
    #
    #   Railsmith.configure do |c|
    #     c.register_coercion(:money, ->(v) { Money.new(v) })
    #   end
    #
    # @param type    [Class, Symbol]  the type key passed to `input :field, <type>`
    # @param coercer [#call]          callable that receives the raw value and returns the coerced value
    def register_coercion(type, coercer)
      @custom_coercions[type] = coercer
    end

    # Returns the hash of custom coercions (keyed by type Class or Symbol).
    def custom_coercions
      @custom_coercions
    end
  end
end
