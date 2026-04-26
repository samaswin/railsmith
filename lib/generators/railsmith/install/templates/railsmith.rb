# frozen_string_literal: true

Railsmith.configure do |config|
  # Set false to skip ActiveSupport::Notifications + plain-Ruby subscribers for
  # all Railsmith instrumentation (service.call, pipelines, cross-domain, etc.).
  # config.instrumentation_enabled = false

  # When true, merging a step's Hash result into accumulated params raises if a key
  # already exists with a different value (default false — last merge wins).
  # config.pipeline_detect_merge_collisions = true

  config.warn_on_cross_domain_calls = true
  config.strict_mode = false
  config.fail_on_arch_violations = false # set true (or use RAILSMITH_FAIL_ON_ARCH_VIOLATIONS) to fail CI on arch checks
  # Approved context_domain → service_domain pairs, e.g.:
  # config.cross_domain_allowlist = [{ from: :billing, to: :catalog }]
  config.on_cross_domain_violation = nil # optional Proc, called on each violation when strict_mode is true

  # Async nested association writes (`async: true` on link_many/link_one)
  #
  # By default Railsmith uses ActiveJob via Railsmith::AsyncNestedWriteJob.
  # This works with SolidQueue/SolidJob, GoodJob, DelayedJob, Sidekiq (via ActiveJob).
  #
  # If you want to override:
  #   config.async_job_class = Railsmith::AsyncNestedWriteJob
  #
  # Sidekiq (native worker, no ActiveJob):
  #   # config.async_job_class = RailsmithNestedWriteWorker
  #
  # Non-ActiveJob backends (e.g. Sneakers) can be supported by providing a custom enqueuer:
  #   # config.async_job_class = RailsmithNestedWriteWorker
  #   # config.async_enqueuer = ->(job_class, payload) { job_class.publish(payload) }
  #
  # Kicks-style publishers are supported out of the box if your class responds to:
  #   - publish_async(payload) or publish(payload)
  # Just set:
  #   # config.async_job_class = MyKicksPublisher
end
