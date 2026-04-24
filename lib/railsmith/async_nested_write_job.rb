# frozen_string_literal: true

require "active_job" unless defined?(ActiveJob::Base)

module Railsmith
  # Default ActiveJob base class for async nested association writes.
  #
  # Enabled by declaring an association with +async: true+ **and** wiring
  # this job (or any ActiveJob subclass with a compatible +#perform+
  # signature) into configuration:
  #
  #   # config/initializers/railsmith.rb
  #   Railsmith.configure do |c|
  #     c.async_job_class = Railsmith::AsyncNestedWriteJob
  #   end
  #
  # The job re-hydrates the original service and re-invokes the nested
  # write for the named association on a fresh parent record. Because the
  # parent transaction has already committed by the time the job runs,
  # failures here cannot roll back the parent — retries are handled via
  # ActiveJob's standard retry / dead-letter machinery, and terminal
  # failures emit an +async_nested_write.failed.railsmith+ event so the
  # app can alert.
  class AsyncNestedWriteJob < ActiveJob::Base
    def perform(service_class:, association:, parent_id:, nested_params:, mode:, context:)
      with_instrumented_failure(**failure_context(service_class, association, parent_id, mode)) do
        perform_nested_write(
          service_class: service_class,
          association: association,
          parent_id: parent_id,
          nested_params: nested_params,
          mode: mode,
          context: context
        )
      end
    end

    private

    def perform_nested_write(service_class:, association:, parent_id:, nested_params:, mode:, context:)
      service_klass, railsmith_context, parent_record =
        resolve_job_state(service_class, context, parent_id)
      invoke_nested_write(
        service_klass: service_klass,
        association: association.to_sym,
        parent_record: parent_record,
        nested_params: nested_params,
        mode: mode.to_sym,
        railsmith_context: railsmith_context
      )
    end

    def failure_context(service_class, association, parent_id, mode)
      { association: association, parent_id: parent_id, service_class: service_class, mode: mode }
    end

    def with_instrumented_failure(association:, parent_id:, service_class:, mode:)
      yield
    rescue StandardError => e
      instrument_failure(
        association: association,
        parent_id: parent_id,
        service_class: service_class,
        mode: mode,
        error: e
      )
      raise
    end

    def resolve_service_class(service_class)
      service_class.is_a?(String) ? Object.const_get(service_class) : service_class
    end

    def resolve_parent_record(service_klass, parent_id)
      service_klass.model.find(parent_id)
    end

    def resolve_job_state(service_class, context, parent_id)
      service_klass = resolve_service_class(service_class)
      railsmith_context = Railsmith::Context.build(context)
      parent_record = resolve_parent_record(service_klass, parent_id)
      [service_klass, railsmith_context, parent_record]
    end

    def invoke_nested_write(service_klass:, association:, parent_record:, nested_params:, mode:, railsmith_context:)
      service_klass
        .new(params: {}, context: railsmith_context)
        .send(:perform_nested_write_for_job, association, parent_record, nested_params, mode)
    end

    def instrument_failure(association:, parent_id:, service_class:, mode:, error:)
      Railsmith::Instrumentation.instrument(
        "async_nested_write.failed",
        association: association.to_sym,
        parent_id: parent_id,
        service: service_class.to_s,
        mode: mode.to_s,
        error_class: error.class.name,
        error: error.message
      )
    end
  end
end
