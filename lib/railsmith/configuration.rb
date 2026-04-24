# frozen_string_literal: true

module Railsmith
  # Stores global settings used by gem components.
  class Configuration
    attr_accessor :warn_on_cross_domain_calls, :strict_mode,
                  :cross_domain_allowlist, :on_cross_domain_violation,
                  :fail_on_arch_violations,
                  :async_job_class,
                  :async_enqueuer,
                  :instrumentation_enabled,
                  :pipeline_detect_merge_collisions

    def initialize
      set_default_flags
      set_default_hook_state
      set_default_async_config
      set_default_instrumentation
      set_default_pipeline_options
    end

    def default_async_job_class
      return nil unless defined?(Railsmith::AsyncNestedWriteJob)

      Railsmith::AsyncNestedWriteJob
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

    def add_global_hook(type, actions, options, &block)
      validate_hook_args!(actions, block)
      global_hooks.add(build_global_hook_entry(type, actions, options, block))
    end

    def validate_hook_args!(actions, block)
      raise ArgumentError, "hook block is required" if block.nil?
      raise ArgumentError, "at least one action symbol is required" if actions.empty?
    end

    def build_global_hook_entry(type, actions, options, block)
      condition, polarity = extract_global_condition(options)
      Railsmith::Hooks::HookEntry.new(
        type: type,
        actions: actions,
        block: block,
        condition: condition,
        polarity: polarity,
        name: options[:name],
        only_domains: options[:only]
      )
    end

    def set_default_flags
      @warn_on_cross_domain_calls = true
      @strict_mode = false
      @cross_domain_allowlist = []
      @on_cross_domain_violation = nil
      @fail_on_arch_violations = false
    end

    def set_default_hook_state
      @custom_coercions = {}
      @global_hooks = nil
    end

    def set_default_async_config
      @async_job_class = default_async_job_class
      @async_enqueuer = nil
    end

    def set_default_instrumentation
      @instrumentation_enabled = true
    end

    def set_default_pipeline_options
      @pipeline_detect_merge_collisions = false
    end

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
