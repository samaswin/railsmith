# frozen_string_literal: true

require "json"

module Railsmith
  class BaseService
    module NestedWriter
      module NestedWrite
        # Async nested write enqueueing helpers extracted to keep WriteNested focused.
        module AsyncEnqueueing
          private

          def enqueue_nested_write(definition, parent_record, nested_params, mode)
            job_class = Railsmith.configuration.async_job_class
            ensure_async_job_configured!(job_class, definition)

            payload = async_nested_write_payload(definition, parent_record, nested_params, mode)
            job_id = enqueue_async_job(job_class, payload)

            instrument_nested_write_enqueued(definition, parent_record, job_id, mode)
            async_nested_write_result(definition, job_id)
          end

          def ensure_async_job_configured!(job_class, definition)
            return if job_class

            raise Railsmith::AsyncNotConfiguredError,
                  "async: true is set on association #{definition.name.inspect} but " \
                  "Railsmith.configuration.async_job_class is not configured. " \
                  "Set `Railsmith.configure { |c| c.async_job_class = MyJob }` " \
                  "to enable background nested writes."
          end

          def async_nested_write_payload(definition, parent_record, nested_params, mode)
            {
              service_class: self.class.name,
              association: definition.name.to_s,
              parent_id: parent_record.id,
              nested_params: nested_params,
              mode: mode.to_s,
              context: context.to_h
            }
          end

          def instrument_nested_write_enqueued(definition, parent_record, job_id, mode)
            Railsmith::Instrumentation.instrument(
              "nested_write.enqueued",
              association: definition.name,
              parent_id: parent_record.id,
              service: definition.service_class.name,
              job_id: job_id,
              mode: mode
            )
          end

          def async_nested_write_result(definition, job_id)
            Result.success(value: nil, meta: { async: true, association: definition.name, job_id: job_id })
          end

          def enqueue_async_job(job_class, payload)
            custom_enqueuer = Railsmith.configuration.async_enqueuer
            return enqueue_via_custom(custom_enqueuer, job_class, payload) if custom_enqueuer

            job_id = enqueue_via_builtin(job_class, payload)
            return job_id unless job_id.nil?

            raise_unsupported_async_job!(job_class)
          end

          def enqueue_via_custom(custom_enqueuer, job_class, payload)
            job_or_id = custom_enqueuer.call(job_class, payload)
            return job_or_id.job_id if job_or_id.respond_to?(:job_id)
            return job_or_id if job_or_id.is_a?(String) || job_or_id.is_a?(Integer)

            nil
          end

          def enqueue_via_builtin(job_class, payload)
            builtin_enqueue_handlers.each do |handler|
              job_id = handler.call(job_class, payload)
              return job_id unless job_id.nil?
            end
            nil
          end

          def builtin_enqueue_handlers
            [
              method(:try_enqueue_via_active_job),
              method(:try_enqueue_via_perform_async),
              method(:try_enqueue_via_publish_async),
              method(:try_enqueue_via_publish),
              method(:try_enqueue_via_enqueue)
            ]
          end

          def try_enqueue_via_active_job(job_class, payload)
            return nil unless job_class.respond_to?(:perform_later)

            enqueue_via_active_job(job_class, payload)
          end

          def try_enqueue_via_perform_async(job_class, payload)
            return nil unless job_class.respond_to?(:perform_async)

            # Sidekiq 7+ (strict_args!) rejects non-JSON-native arg types (e.g. Symbol keys).
            # Keep the payload JSON-safe for Sidekiq-style enqueueing.
            json_native_payload = JSON.parse(JSON.generate(payload.deep_stringify_keys))
            job_class.perform_async(json_native_payload)
          end

          def try_enqueue_via_publish_async(job_class, payload)
            return nil unless job_class.respond_to?(:publish_async)

            job_class.publish_async(payload)
          end

          def try_enqueue_via_publish(job_class, payload)
            return nil unless job_class.respond_to?(:publish)

            enqueue_via_publish(job_class, payload)
          end

          def try_enqueue_via_enqueue(job_class, payload)
            return nil unless job_class.respond_to?(:enqueue)

            enqueue_via_enqueue(job_class, payload)
          end

          def enqueue_via_active_job(job_class, payload)
            job = job_class.perform_later(**payload)
            job.respond_to?(:job_id) ? job.job_id : nil
          end

          def enqueue_via_publish(job_class, payload)
            job_or_id = job_class.publish(payload)
            return job_or_id.job_id if job_or_id.respond_to?(:job_id)
            return job_or_id if job_or_id.is_a?(String) || job_or_id.is_a?(Integer)

            nil
          end

          def enqueue_via_enqueue(job_class, payload)
            job = job_class.enqueue(payload)
            job.respond_to?(:job_id) ? job.job_id : nil
          end

          def raise_unsupported_async_job!(job_class)
            raise Railsmith::AsyncNotConfiguredError,
                  "Railsmith.configuration.async_job_class (#{job_class}) does not support enqueueing. " \
                  "Expected .perform_later(**payload) (ActiveJob), .perform_async(payload) (Sidekiq), " \
                  ".publish_async(payload) / .publish(payload) (Kicks-style), " \
                  "or configure Railsmith.configuration.async_enqueuer."
          end
        end
      end
    end
  end
end
