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
      # @param name     [Symbol]          identifier used in events and error meta
      # @param service  [Class]           a Railsmith::BaseService subclass
      # @param action   [Symbol]          action forwarded to service.call(action:)
      # @param inputs   [Hash, nil]       optional { target_key => source_key } renames
      # @param rollback [Symbol, Proc, nil]
      #   Compensation handler invoked (in reverse step order) when a later step fails.
      #
      #   Symbol — treated as an action name on the same service class. The service is
      #   invoked via service.call(action: rollback, params:, context:) where params
      #   is the params forwarded to the forward step merged with that step's result.value
      #   (when it is a Hash), giving the rollback handler all the IDs it needs to undo work.
      #
      #   Proc — called as rollback.call(step_result, context) where step_result is the
      #   Result returned by the forward step and context is the pipeline Context.
      #
      #   Idempotency: rollback handlers SHOULD be idempotent. The pipeline makes no
      #   guarantees about exactly-once delivery — a rollback may be retried on infra
      #   failure. Design handlers to be safe when called multiple times (e.g. check
      #   whether a reservation still exists before cancelling it).
      def step(name, service:, action:, inputs: nil, rollback: nil)
        step_definitions << StepDefinition.new(
          name:     name.to_sym,
          service:  service,
          action:   action.to_sym,
          inputs:   inputs,
          rollback: rollback
        )
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

      # Subclasses start with a private copy of the parent's step list so
      # additional steps declared on the subclass do not leak back upward.
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@step_definitions, step_definitions.dup)
      end
    end
  end
end
