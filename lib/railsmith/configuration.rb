# frozen_string_literal: true

module Railsmith
  # Stores global settings used by gem components.
  class Configuration
    attr_accessor :warn_on_cross_domain_calls, :strict_mode,
                  :cross_domain_allowlist, :on_cross_domain_violation,
                  :fail_on_arch_violations,
                  :async_job_class

    def initialize
      @warn_on_cross_domain_calls = true
      @strict_mode = false
      @cross_domain_allowlist = []
      @on_cross_domain_violation = nil
      @fail_on_arch_violations = false
      @custom_coercions = {}
      @global_hooks = nil
      @async_job_class = nil
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
    attr_reader :custom_coercions

    # --- Global lifecycle hooks ----------------------------------------------
    #
    # Global hooks run on every service action matching the given action name.
    # They fire *before* class-level hooks in the execution sandwich, so a
    # rate-limiter declared here wraps every subclass's local callbacks.
    #
    #   Railsmith.configure do |config|
    #     config.before_action :create do
    #       RateLimiter.check!(context[:actor_id])
    #     end
    #
    #     config.around_action :create, only: [:commerce] do |action|
    #       CommerceSandbox.wrap { action.call }
    #     end
    #   end
    #
    # Pass +only:+ to restrict a hook to services whose declared +domain+ is
    # in the list. Pass +name:+ to allow subclasses to +skip_hook+ by name.

    # The live HookRegistry holding every globally declared hook. Tests can
    # reset it via +reset_global_hooks!+ between examples.
    def global_hooks
      @global_hooks ||= Railsmith::Hooks::HookRegistry.new
    end

    # Clear every global hook. Primarily useful in test teardown.
    def reset_global_hooks!
      @global_hooks = nil
    end

    def before_action(*actions, **options, &)
      add_global_hook(:before, actions, options, &)
    end

    def after_action(*actions, **options, &)
      add_global_hook(:after, actions, options, &)
    end

    def around_action(*actions, **options, &)
      add_global_hook(:around, actions, options, &)
    end

    private

    # rubocop:disable Metrics/MethodLength
    def add_global_hook(type, actions, options, &block)
      raise ArgumentError, "hook block is required" if block.nil?
      raise ArgumentError, "at least one action symbol is required" if actions.empty?

      condition, polarity = extract_global_condition(options)
      global_hooks.add(
        Railsmith::Hooks::HookEntry.new(
          type: type,
          actions: actions,
          block: block,
          condition: condition,
          polarity: polarity,
          name: options[:name],
          only_domains: options[:only]
        )
      )
    end
    # rubocop:enable Metrics/MethodLength

    def extract_global_condition(options)
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
end
