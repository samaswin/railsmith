# frozen_string_literal: true

module Railsmith
  class Pipeline
    # Walks a pipeline's step definitions, invoking each step's service and
    # accumulating params across steps. Emits instrumentation events at each
    # step boundary and for the overall pipeline run.
    #
    # Execution is fail-fast: on the first step failure the runner invokes
    # rollback handlers (in reverse order) for every previously completed step
    # that declared a rollback:, then returns a failure Result annotated with
    # :pipeline_name, :pipeline_step, and (when present) :rollback_failures in meta.
    #
    # Param forwarding rule:
    #   accumulated_params starts as the original params hash. After each
    #   successful step, if result.value is a Hash, it is merged into
    #   accumulated_params so the next step receives everything seen so far.
    #   Steps with an inputs: mapping have source keys renamed to target keys
    #   in the copy forwarded to that step; accumulated_params itself retains
    #   the original key names.
    class Runner
      ExecutedStep = Struct.new(:step_def, :params_used, :result, keyword_init: true)

      def initialize(pipeline_class:, params:, context:)
        @pipeline_class     = pipeline_class
        @context            = context
        @accumulated_params = params.dup
        @executed_steps     = []
      end

      def run
        pipeline_name = @pipeline_class.pipeline_name
        started_at    = clock_now
        result        = execute_steps

        Instrumentation.instrument("pipeline", {
                                     pipeline: pipeline_name,
                                     status: result.success? ? :success : :failure,
                                     duration: clock_now - started_at
                                   })

        result
      end

      private

      def execute_steps
        last_result = run_each_step
        last_result || Result.success(value: nil)
      end

      def run_each_step
        last_result = nil
        @pipeline_class.step_definitions.each do |step_def|
          step_outcome = run_one_step(step_def)
          return step_outcome if step_outcome.is_a?(Result)

          last_result = step_outcome if step_outcome
        end
        last_result
      end

      def run_one_step(step_def)
        return nil if skip_step?(step_def)

        params_for_step = step_def.resolve_params(@accumulated_params)
        step_result = execute_step(step_def, params_for_step)
        return handle_step_failure(step_def, step_result) if step_result.failure?

        record_successful_step(step_def, params_for_step, step_result)
        merge_value_into_accumulated(step_result.value, step_def)
        step_result
      end

      def skip_step?(step_def)
        return false unless step_def.skip?(@accumulated_params, @context, @pipeline_class.guards)

        emit_skipped_event(step_def)
        true
      end

      def handle_step_failure(step_def, step_result)
        return nil if step_def.continue_on_failure?

        rollback_failures = run_rollbacks
        wrap_failure(step_result, step_def, rollback_failures)
      end

      def record_successful_step(step_def, params_for_step, step_result)
        @executed_steps << ExecutedStep.new(
          step_def: step_def,
          params_used: params_for_step,
          result: step_result
        )
      end

      def emit_skipped_event(step_def)
        Instrumentation.instrument("pipeline.step.skipped", {
                                     pipeline: @pipeline_class.pipeline_name,
                                     step: step_def.name
                                   })
      end

      def execute_step(step_def, params)
        pipeline_name = @pipeline_class.pipeline_name
        started_at    = clock_now

        raw = step_def.service.call(action: step_def.action, params: params, context: @context)

        Instrumentation.instrument("pipeline.step", {
                                     pipeline: pipeline_name,
                                     step: step_def.name,
                                     status: raw.success? ? :success : :failure,
                                     duration: clock_now - started_at
                                   })

        raw
      end

      # Walk successfully executed steps in reverse order, invoking each rollback
      # handler. Collects failures from individual rollbacks without aborting the
      # compensation sequence — every step gets a chance to roll back.
      #
      # Returns an Array of { step:, error: } hashes for each failed rollback.
      def run_rollbacks
        failures = []

        @executed_steps.reverse_each do |entry|
          next unless entry.step_def.rollback?

          failed = invoke_rollback(entry.step_def, entry.params_used, entry.result)
          failures << { step: entry.step_def.name, error: failed.error } if failed
        end

        failures
      end

      # Invoke a single step's rollback handler. Returns the failure Result if the
      # rollback itself fails, nil on success.
      def invoke_rollback(step_def, params_used, step_result)
        rollback_params = build_rollback_params(params_used, step_result)
        started_at = clock_now
        raw = execute_rollback(step_def, rollback_params, step_result)

        instrument_rollback(step_def, raw, started_at)
        raw.failure? ? raw : nil
      end

      def execute_rollback(step_def, rollback_params, step_result)
        handler = step_def.rollback
        return call_rollback_action(step_def, handler, rollback_params) if handler.is_a?(Symbol)
        return call_rollback_proc(handler, step_result) if handler.is_a?(Proc)

        nil
      end

      def call_rollback_action(step_def, action_name, rollback_params)
        step_def.service.call(
          action: action_name,
          params: rollback_params,
          context: @context
        )
      end

      def call_rollback_proc(proc_handler, step_result)
        outcome = proc_handler.call(step_result, @context)
        outcome.is_a?(Result) ? outcome : Result.success
      rescue StandardError => e
        Result.failure(code: :unexpected, message: e.message)
      end

      def instrument_rollback(step_def, raw, started_at)
        Instrumentation.instrument("pipeline.rollback", {
                                     pipeline: @pipeline_class.pipeline_name,
                                     step: step_def.name,
                                     status: raw.success? ? :success : :failure,
                                     duration: clock_now - started_at
                                   })
      end

      # Build params to pass to the rollback handler: the params forwarded to the
      # forward step, merged with the step's result.value when it is a Hash.
      def build_rollback_params(params_used, step_result)
        return params_used.dup unless step_result.value.is_a?(Hash)

        params_used.merge(step_result.value)
      end

      # Merge a step's result value into accumulated params, but only when
      # the value is a Hash. Non-Hash values (ActiveRecord objects, etc.) are
      # skipped so callers can still return domain objects without polluting params.
      def merge_value_into_accumulated(value, step_def)
        return unless value.is_a?(Hash)

        if Railsmith.configuration.pipeline_detect_merge_collisions
          value.each do |key, incoming|
            next unless @accumulated_params.key?(key)

            existing = @accumulated_params[key]
            next if existing == incoming

            raise Pipeline::ParamCollisionError.new(step_def.name, key, existing, incoming)
          end
        end

        @accumulated_params = @accumulated_params.merge(value)
      end

      def wrap_failure(step_result, step_def, rollback_failures = [])
        meta = step_result.meta.merge(
          pipeline_name: @pipeline_class.pipeline_name,
          pipeline_step: step_def.name
        )
        meta[:rollback_failures] = rollback_failures unless rollback_failures.empty?

        Result.failure(
          error: step_result.error,
          meta: meta
        )
      end

      def clock_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
