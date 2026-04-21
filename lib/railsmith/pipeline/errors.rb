# frozen_string_literal: true

module Railsmith
  class Pipeline
    # Raised when an inputs: mapping references a key absent from accumulated params.
    class ParamMappingError < StandardError
      def initialize(step_name, source_key)
        super("Pipeline step :#{step_name} inputs: mapping references :#{source_key} " \
              "which is not present in accumulated params")
      end
    end

    # Raised when a step's if:/unless: references a guard name not registered on
    # the pipeline via the guard helper.
    class GuardNotFoundError < StandardError
      def initialize(guard_name)
        super("Pipeline guard :#{guard_name} is not defined on this pipeline")
      end
    end
  end
end
