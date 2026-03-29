# frozen_string_literal: true

require "securerandom"

module Railsmith
  # Immutable value object for propagating request context through service calls.
  # Accepts +domain:+ plus any number of extra keyword args (actor_id, request_id, etc.)
  # stored at the top level — no nested +:meta+ hash needed.
  #
  # Example:
  #   ctx = Railsmith::Context.new(domain: :billing, actor_id: 42)
  #   BillingService.call(action: :create, params: params, context: ctx.to_h)
  #
  # Accessing extras:
  #   ctx[:actor_id]   # => 42
  #   ctx.to_h         # => { current_domain: :billing, actor_id: 42 }
  class Context
    # Normalizes a domain value to a Symbol (or nil for blank/nil input).
    def self.normalize_current_domain(value)
      return nil if value.nil?
      return nil if value.is_a?(String) && value.strip.empty?
      return value if value.is_a?(Symbol)

      value.respond_to?(:to_sym) ? value.to_sym : value
    end

    # @param domain [Symbol, String, nil] bounded-context key (preferred kwarg)
    # @param current_domain [Symbol, String, nil] deprecated alias for +domain:+
    # @param extras [Hash] arbitrary extra keys stored at the top level
    def initialize(domain: nil, current_domain: nil, **extras)
      if !current_domain.nil? && domain.nil?
        warn "[DEPRECATION] Railsmith::Context: `current_domain:` is deprecated; use `domain:` instead."
        domain = current_domain
      end

      @domain = self.class.normalize_current_domain(domain)
      extras[:request_id] ||= SecureRandom.uuid
      @extras = extras.freeze
      freeze
    end

    attr_reader :domain

    # Returns the request ID (auto-generated UUID if not supplied at construction).
    def request_id
      @extras[:request_id]
    end

    # Backward-compatible reader — returns the same value as +domain+.
    def current_domain
      @domain
    end

    # Accesses extra keys by symbol.
    def [](key)
      sym = key.to_sym
      return @domain if sym == :current_domain || sym == :domain

      @extras[sym]
    end

    # Returns true when no domain has been set.
    def blank_domain?
      @domain.nil?
    end

    # Serializes to a plain hash.
    # Uses +:current_domain+ as the domain key for backward compatibility with
    # services that read +context[:current_domain]+ directly.
    def to_h
      { current_domain: @domain }.merge(@extras)
    end
  end
end
