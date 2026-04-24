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
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def perform(service_class:, association:, parent_id:, nested_params:, mode:, context:)
      svc_class     = service_class.is_a?(String) ? Object.const_get(service_class) : service_class
      ctx           = Railsmith::Context.build(context)
      mode_sym      = mode.to_sym
      assoc_sym     = association.to_sym

      parent_model  = svc_class.model
      parent_record = parent_model.find(parent_id)

      svc = svc_class.new(params: {}, context: ctx)
      svc.send(
        :perform_nested_write_for_job,
        assoc_sym,
        parent_record,
        nested_params,
        mode_sym
      )
    rescue StandardError => e
      Railsmith::Instrumentation.instrument(
        "async_nested_write.failed",
        association: association.to_sym,
        parent_id: parent_id,
        service: service_class.to_s,
        mode: mode.to_s,
        error_class: e.class.name,
        error: e.message
      )
      raise
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
  end
end
