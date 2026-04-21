# frozen_string_literal: true

module Railsmith
  class Pipeline
    # Walks a pipeline's step definitions, invoking each step's service and
    # accumulating params across steps. Emits instrumentation events at each
    # step boundary and for the overall pipeline run.
    #
    # Execution is fail-fast: on the first step failure the runner returns
    # that failure Result immediately, wrapped with :pipeline_name and
    # :pipeline_step in the meta hash. Subsequent steps are not called.
    #
    # Param forwarding rule:
    #   accumulated_params starts as the original params hash. After each
    #   successful step, if result.value is a Hash, it is merged into
    #   accumulated_params so the next step receives everything seen so far.
    #   Steps with an inputs: mapping have source keys renamed to target keys
    #   in the copy forwarded to that step; accumulated_params itself retains
    #   the original key names.
    class Runner
      def initialize(pipeline_class:, params:, context:)
        @pipeline_class    = pipeline_class
        @context           = context
        @accumulated_params = params.dup
      end

      def run
        pipeline_name = @pipeline_class.pipeline_name
        started_at    = clock_now
        result        = execute_steps

        Instrumentation.instrument("pipeline", {
          pipeline: pipeline_name,
          status:   result.success? ? :success : :failure,
          duration: clock_now - started_at
        })

        result
      end

      private

      def execute_steps
        last_result = nil

        @pipeline_class.step_definitions.each do |step_def|
          step_result = execute_step(step_def)
          return step_result if step_result.failure?

          last_result = step_result
          merge_value_into_accumulated(step_result.value)
        end

        # An empty pipeline succeeds with nil value; non-empty returns last step's result.
        last_result || Result.success(value: nil)
      end

      def execute_step(step_def)
        pipeline_name = @pipeline_class.pipeline_name
        params        = step_def.resolve_params(@accumulated_params)
        started_at    = clock_now

        raw = step_def.service.call(action: step_def.action, params: params, context: @context)

        Instrumentation.instrument("pipeline.step", {
          pipeline: pipeline_name,
          step:     step_def.name,
          status:   raw.success? ? :success : :failure,
          duration: clock_now - started_at
        })

        raw.success? ? raw : wrap_failure(raw, step_def)
      end

      # Merge a step's result value into accumulated params, but only when
      # the value is a Hash. Non-Hash values (ActiveRecord objects, etc.) are
      # skipped so callers can still return domain objects without polluting params.
      def merge_value_into_accumulated(value)
        return unless value.is_a?(Hash)

        @accumulated_params = @accumulated_params.merge(value)
      end

      def wrap_failure(step_result, step_def)
        Result.failure(
          error: step_result.error,
          meta:  step_result.meta.merge(
            pipeline_name: @pipeline_class.pipeline_name,
            pipeline_step: step_def.name
          )
        )
      end

      def clock_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
