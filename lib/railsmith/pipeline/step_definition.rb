# frozen_string_literal: true

module Railsmith
  class Pipeline
    # Immutable record describing a single declared pipeline step.
    #
    # name               - symbolic identifier used in instrumentation and error messages
    # service            - a BaseService subclass (the class itself, not an instance)
    # action             - the action symbol to invoke on that service
    # inputs             - optional Hash of { target_key => source_key } renames applied to
    #                      accumulated params before they are forwarded to this step's service;
    #                      raises ParamMappingError when a source_key is absent
    # rollback           - optional Symbol (action name on service) or Proc invoked when a later
    #                      step fails; used to undo this step's side-effects
    # condition          - optional Symbol (named guard) or Proc evaluated against
    #                      (accumulated_params, context); combined with polarity to decide skip
    # polarity           - :if (run when condition is truthy) or :unless (run when falsy)
    # on_failure_continue - when true, a failure from this step does not halt the pipeline
    StepDefinition = Struct.new(
      :name, :service, :action, :inputs, :rollback,
      :condition, :polarity, :on_failure_continue,
      keyword_init: true
    ) do
      def has_rollback?
        !rollback.nil?
      end

      def continue_on_failure?
        !!on_failure_continue
      end

      # Returns true when this step should be skipped for the given execution context.
      #
      # accumulated_params - the current accumulated params Hash
      # context            - the pipeline's Railsmith::Context
      # guards             - Hash of { name_sym => Proc } registered on the pipeline
      def skip?(accumulated_params, context, guards = {})
        return false if condition.nil?

        raw = evaluate_condition(accumulated_params, context, guards)
        polarity == :if ? !raw : !!raw
      end

      # Resolve the params to pass to this step's service.
      #
      # accumulated - the current accumulated params Hash
      #
      # Returns a new Hash ready to be forwarded as params: to the service call.
      # When inputs: is present, each { target => source } pair replaces source_key
      # with target_key in the forwarded hash; the rest of accumulated passes through.
      def resolve_params(accumulated)
        return accumulated.dup if inputs.nil? || inputs.empty?

        result = accumulated.dup
        inputs.each do |target_key, source_key|
          unless result.key?(source_key)
            raise Pipeline::ParamMappingError.new(name, source_key)
          end

          next if target_key == source_key

          result[target_key] = result.delete(source_key)
        end
        result
      end

      private

      def evaluate_condition(accumulated_params, context, guards)
        case condition
        when Symbol
          guard_proc = guards[condition]
          raise Pipeline::GuardNotFoundError.new(condition) unless guard_proc

          guard_proc.call(accumulated_params, context)
        when Proc
          condition.call(accumulated_params, context)
        else
          !!condition
        end
      end
    end
  end
end
