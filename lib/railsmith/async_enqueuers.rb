# frozen_string_literal: true

module Railsmith
  # Small helpers for enqueueing async work across job backends.
  #
  # The nested-writes feature primarily targets ActiveJob, which in turn can be
  # backed by SolidQueue/SolidJob, GoodJob, DelayedJob, Sidekiq, etc.
  #
  # For non-ActiveJob systems (e.g. Sneakers), apps can provide
  # `Railsmith.configuration.async_enqueuer` and call into their queue client
  # while keeping the same payload contract.
  module AsyncEnqueuers
    module_function

    # Enqueue via ActiveJob-style `.perform_later(**payload)`.
    # Returns a job_id when available; otherwise nil.
    def active_job(job_class, payload)
      job = job_class.perform_later(**payload)
      job.respond_to?(:job_id) ? job.job_id : nil
    end

    # Enqueue via Sidekiq-style `.perform_async(payload_hash)`.
    # Returns the Sidekiq JID (String) when provided by the backend.
    def sidekiq(job_class, payload)
      job_class.perform_async(payload)
    end

    # Generic enqueue helper for custom systems.
    # The default nested-writer code will call this only if you wire it in as
    # `config.async_enqueuer`.
    def call(enqueuer, job_class, payload)
      job_or_id = enqueuer.call(job_class, payload)
      return job_or_id.job_id if job_or_id.respond_to?(:job_id)
      return job_or_id if job_or_id.is_a?(String) || job_or_id.is_a?(Integer)

      nil
    end
  end
end
