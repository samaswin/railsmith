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
    THREAD_KEY = :railsmith_context
    private_constant :THREAD_KEY

    # Returns the thread-local +Context+ set by +.with+, or +nil+.
    def self.current
      Thread.current[THREAD_KEY]
    end

    # Sets the thread-local +Context+ directly. Prefer +.with+ for scoped use.
    def self.current=(ctx)
      Thread.current[THREAD_KEY] = ctx
    end

    # Runs +block+ with a thread-local context built from the given kwargs (or
    # an existing +Context+ instance). Restores the previous value afterwards,
    # even if the block raises.
    #
    #   Railsmith::Context.with(domain: :web, actor_id: 42) do
    #     UserService.call(action: :create, params: { ... })
    #   end
    def self.with(context = nil, **kwargs)
      ctx = if context.is_a?(Context)
               context
             elsif !kwargs.empty?
               new(**kwargs)
             else
               new
             end

      previous = current
      self.current = ctx
      begin
        yield
      ensure
        self.current = previous
      end
    end

    # Coerces any context-like value into a +Context+ instance.
    #
    # - +Context+ → returned as-is
    # - +nil+ or +{}+ → +Context.new+ with auto-generated +request_id+
    # - Hash → deep-duped and wrapped in +Context.new+; +:current_domain+ is
    #   remapped to +:domain+ so the deprecated alias path is never triggered
    def self.build(context)
      case context
      when Context
        context
      when nil
        new
      when Hash
        return new if context.empty?

        kwargs = Railsmith.deep_dup(context)
        kwargs[:domain] = kwargs.delete(:current_domain) if kwargs.key?(:current_domain) && !kwargs.key?(:domain)
        new(**kwargs)
      else
        new
      end
    end

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
