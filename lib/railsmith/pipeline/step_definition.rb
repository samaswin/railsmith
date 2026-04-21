# frozen_string_literal: true

module Railsmith
  class Pipeline
    # Immutable record describing a single declared pipeline step.
    #
    # name    - symbolic identifier used in instrumentation and error messages
    # service - a BaseService subclass (the class itself, not an instance)
    # action  - the action symbol to invoke on that service
    # inputs  - optional Hash of { target_key => source_key } renames applied to
    #           accumulated params before they are forwarded to this step's service;
    #           raises ParamMappingError when a source_key is absent
    StepDefinition = Struct.new(:name, :service, :action, :inputs, keyword_init: true) do
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
    end
  end
end
