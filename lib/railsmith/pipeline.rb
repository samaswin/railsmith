# frozen_string_literal: true

module Railsmith
  require_relative "pipeline/errors"
  require_relative "pipeline/step_definition"
  require_relative "pipeline/runner"

  # Sequential service composition with fail-fast semantics.
  #
  # A pipeline declares an ordered list of steps, each backed by a
  # Railsmith::BaseService subclass. On each call, the Runner walks the steps
  # in order, merging the previous step's result.value (when it is a Hash)
  # into the accumulated params so the next step receives everything seen so
  # far. On the first failure the pipeline halts and returns that failure
  # Result, annotated with :pipeline_name and :pipeline_step in meta.
  #
  # == Basic usage
  #
  #   class CheckoutPipeline < Railsmith::Pipeline
  #     step :validate_cart,      service: CartService,         action: :validate
  #     step :reserve_inventory,  service: InventoryService,    action: :reserve,
  #                               rollback: :unreserve
  #     step :charge_payment,     service: PaymentService,      action: :charge,
  #                               inputs: { amount: :cart_total }, rollback: :refund
  #     step :send_confirmation,  service: NotificationService, action: :send_receipt
  #   end
  #
  #   result = CheckoutPipeline.call(params: { cart_id: 42, user_id: 7 })
  #   result.success?                    # => true
  #   result.meta[:pipeline_name]        # => "CheckoutPipeline" (on failure only)
  #
  # == Param forwarding
  #
  # Each step receives +accumulated_params+, which starts as the original params
  # and grows as each step's Hash result.value is merged in.  Use +inputs:+ to
  # rename keys before they reach a specific step's service:
  #
  #   step :charge, service: PaymentService, action: :charge,
  #        inputs: { amount: :cart_total }
  #
  # This renames the :cart_total key to :amount for PaymentService only;
  # subsequent steps still see :cart_total in accumulated params.
  #
  # == Instrumentation
  #
  # Two events are emitted per run:
  #   "pipeline.step.railsmith"  — fired for each step; payload includes
  #                                :pipeline, :step, :status, :duration
  #   "pipeline.railsmith"       — fired once on completion; payload includes
  #                                :pipeline, :status, :duration
  class Pipeline
    UNSET_CONTEXT = Object.new.freeze
    private_constant :UNSET_CONTEXT

    class << self
      # Declare a step in execution order.
      #
      # @param name               [Symbol]          identifier used in events and error meta
      # @param service            [Class]           a Railsmith::BaseService subclass
      # @param action             [Symbol]          action forwarded to service.call(action:)
      # @param inputs             [Hash, nil]       optional { target_key => source_key } renames
      # @param rollback           [Symbol, Proc, nil]
      #   Compensation handler invoked (in reverse step order) when a later step fails.
      #   Symbol — action name on the same service. Proc — called as proc.call(step_result, ctx).
      # @param if      [Symbol, Proc, nil]
      #   Guard condition: step is executed only when the proc/guard returns truthy.
      #   Proc form: ->(params, ctx) { ... }; Symbol form: a named guard declared via +guard+.
      # @param unless  [Symbol, Proc, nil]
      #   Inverse guard: step is skipped when the proc/guard returns truthy.
      # @param on_failure_continue [Boolean]
      #   When true, a failure from this step does not halt the pipeline; subsequent
      #   steps run as if the step was skipped. The failed step is not rolled back.
      def step(name, service:, action:, inputs: nil, rollback: nil, **options)
        condition, polarity = extract_step_condition(options)
        on_failure_continue = options.fetch(:on_failure_continue, false)

        step_definitions << StepDefinition.new(
          name:               name.to_sym,
          service:            service,
          action:             action.to_sym,
          inputs:             inputs,
          rollback:           rollback,
          condition:          condition,
          polarity:           polarity,
          on_failure_continue: on_failure_continue
        )
      end

      # Register a named guard predicate for use in step +if:+/+unless:+ options.
      #
      #   guard :has_coupon? do |params, ctx|
      #     params.key?(:coupon_code)
      #   end
      #
      #   step :apply_coupon, service: CouponService, action: :apply, if: :has_coupon?
      #
      # The block receives (accumulated_params, context) and must return a truthy/falsy value.
      def guard(name, &block)
        raise ArgumentError, "guard block is required" if block.nil?

        guards[name.to_sym] = block
      end

      # Registered named guard predicates for this pipeline class.
      def guards
        @guards ||= {}
      end

      # Ordered list of StepDefinition records for this pipeline class.
      def step_definitions
        @step_definitions ||= []
      end

      # Human-readable name used in instrumentation payloads.
      def pipeline_name
        name || "AnonymousPipeline"
      end

      # Run the pipeline and return a Result.
      #
      # @param params  [Hash]    initial params forwarded to the first step
      # @param context [Hash, Railsmith::Context, nil]
      def call(params: {}, context: UNSET_CONTEXT)
        resolved =
          if context.equal?(UNSET_CONTEXT)
            Context.current || Context.build(nil)
          else
            Context.build(context)
          end
        Runner.new(pipeline_class: self, params: params, context: resolved).run
      end

      # Run the pipeline; raise Railsmith::Failure on the first step failure.
      def call!(params: {}, context: UNSET_CONTEXT)
        result = call(params: params, context: context)
        raise Railsmith::Failure, result if result.failure?

        result
      end

      # Subclasses start with private copies of the parent's step list and guard
      # registry so additions on the subclass do not leak back upward.
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@step_definitions, step_definitions.dup)
        subclass.instance_variable_set(:@guards, guards.dup)
      end

      private

      def extract_step_condition(options)
        if options.key?(:if) && options.key?(:unless)
          raise ArgumentError, "cannot declare both if: and unless: on the same step"
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
end
