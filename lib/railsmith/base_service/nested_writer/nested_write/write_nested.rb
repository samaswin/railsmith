# frozen_string_literal: true

module Railsmith
  class BaseService
    module NestedWriter
      module NestedWrite
        # Writes nested association params for a parent record.
        module WriteNested
          private

          def write_nested_after_create(parent_record)
            write_nested(parent_record, @params, :create)
          end

          def write_nested_after_update(parent_record)
            write_nested(parent_record, @params, :update)
          end

          def write_nested_for_item(parent_record, item_params, mode)
            write_nested(parent_record, item_params, mode)
          end

          # Entry point used by {Railsmith::AsyncNestedWriteJob} to re-run the
          # nested write for a single association inline (i.e. bypassing the
          # async branch in +perform_nested_write+, which would otherwise
          # re-enqueue the same work forever).
          #
          # @param association [Symbol]               declared association name
          # @param parent_record [ActiveRecord::Base] re-resolved parent
          # @param nested_params                      params for the association key
          # @param mode        [:create, :update]     which flow to run
          # @return [Result]
          def perform_nested_write_for_job(association, parent_record, nested_params, mode)
            definition = self.class.association_registry[association]
            raise ArgumentError, "unknown association #{association.inspect}" unless definition

            source_params = { association => nested_params }

            if definition.kind == :belongs_to
              write_belongs_to(definition, nested_params, parent_record, mode)
            else
              foreign_key = definition.inferred_foreign_key(model_class)
              dispatch_nested(definition, source_params[definition.name], foreign_key, parent_record.id, mode)
            end
          end

          def write_nested(parent_record, source_params, mode)
            registry = self.class.association_registry
            return Result.success(value: parent_record) unless registry.any?

            nested_meta = write_each_nested(registry.all, parent_record, source_params, mode)
            return nested_meta if nested_meta.failure?

            Result.success(value: parent_record, meta: nested_meta_meta(nested_meta.value))
          end

          def write_each_nested(definitions, parent_record, source_params, mode)
            nested_meta = {}
            definitions.each do |definition|
              result = write_one_nested(definition, parent_record, source_params, mode, nested_meta)
              return result if result.failure?
            end

            Result.success(value: nested_meta)
          end

          def write_one_nested(definition, parent_record, source_params, mode, nested_meta)
            return Result.success(value: nil) unless nested_write_target?(definition, source_params)

            result = perform_nested_write(definition, parent_record, source_params, mode)
            return result if result.failure?

            nested_meta[definition.name] = result.meta if result.meta
            Result.success(value: nil)
          end

          def nested_write_target?(definition, source_params)
            nested_params_present?(source_params, definition)
          end

          def perform_nested_write(definition, parent_record, source_params, mode)
            nested_params = source_params[definition.name]
            if definition.async?
              return enqueue_nested_write(definition, parent_record, nested_params, mode)
            end

            if definition.kind == :belongs_to
              write_belongs_to(definition, nested_params, parent_record, mode)
            else
              foreign_key = definition.inferred_foreign_key(model_class)
              dispatch_nested(definition, nested_params, foreign_key, parent_record.id, mode)
            end
          end

          # Enqueues an async nested write job for +definition+ instead of
          # performing the write inline inside the parent's transaction.
          #
          # The job runs *after* the parent transaction commits, so child
          # failures cannot roll back the parent — retries and dead-lettering
          # are the app's responsibility (configure via ActiveJob).
          #
          # @raise [Railsmith::AsyncNotConfiguredError] when no async_job_class
          #   is configured on +Railsmith.configuration+.
          def enqueue_nested_write(definition, parent_record, nested_params, mode)
            job_class = Railsmith.configuration.async_job_class
            unless job_class
              raise Railsmith::AsyncNotConfiguredError,
                    "async: true is set on association #{definition.name.inspect} but " \
                    "Railsmith.configuration.async_job_class is not configured. " \
                    "Set `Railsmith.configure { |c| c.async_job_class = MyJob }` " \
                    "to enable background nested writes."
            end

            job = job_class.perform_later(
              service_class: definition.service_class.name,
              association:   definition.name.to_s,
              parent_id:     parent_record.id,
              nested_params: nested_params,
              mode:          mode.to_s,
              context:       context.to_h
            )

            job_id = job.respond_to?(:job_id) ? job.job_id : nil

            Railsmith::Instrumentation.instrument(
              "nested_write.enqueued",
              association: definition.name,
              parent_id:   parent_record.id,
              service:     definition.service_class.name,
              job_id:      job_id,
              mode:        mode
            )

            Result.success(
              value: nil,
              meta:  { async: true, association: definition.name, job_id: job_id }
            )
          end

          def nested_params_present?(source_params, definition)
            source_params.is_a?(Hash) && source_params.key?(definition.name)
          end

          def nested_meta_meta(nested_meta)
            return nil if nested_meta.empty?

            { nested: nested_meta }
          end

          def dispatch_nested(definition, nested_params, foreign_key, foreign_value, mode)
            case definition.kind
            when :has_many then write_has_many(definition, nested_params, foreign_key, foreign_value, mode)
            when :has_one  then write_has_one(definition, nested_params, foreign_key, foreign_value, mode)
            else                Result.success(value: nil)
            end
          end

          def write_has_many(definition, nested_params, foreign_key, foreign_value, mode)
            return Result.success(value: []) unless nested_params.is_a?(Array)

            values = []
            nested_params.each do |item_params|
              result = write_nested_item(definition, item_params, foreign_key, foreign_value, mode)
              return result if result.failure?

              values << result.value
            end

            total = nested_params.size
            Result.success(value: values, meta: { total: total, success_count: total, failure_count: 0 })
          end

          def write_has_one(definition, nested_params, foreign_key, foreign_value, mode)
            return Result.success(value: nil) unless nested_params.is_a?(Hash)

            write_nested_item(definition, nested_params, foreign_key, foreign_value, mode)
          end

          def write_belongs_to(definition, nested_params, parent_record, _mode)
            return Result.success(value: nil) unless nested_params.is_a?(Hash)

            foreign_key = definition.inferred_foreign_key(model_class)
            item_id = nested_params[:id] || nested_params["id"]
            destroy_flag = nested_params[:_destroy] || nested_params["_destroy"]

            if truthy_destroy_flag?(destroy_flag)
              return write_belongs_to_destroy(definition, item_id, parent_record, foreign_key)
            end

            write_belongs_to_upsert(definition, item_id, nested_params, parent_record, foreign_key)
          end

          def write_belongs_to_destroy(definition, item_id, parent_record, foreign_key)
            # Nullify the FK first so destroying the parent doesn't cascade
            # back into destroying this record via dependent associations.
            parent_record.update!(foreign_key => nil)

            return Result.success(value: nil) unless item_id

            call_nested_service(definition, :destroy, params: { id: item_id })
          end

          def write_belongs_to_upsert(definition, item_id, nested_params, parent_record, foreign_key)
            attrs = extract_attributes(nested_params)
            result = if item_id
                       call_nested_service(definition, :update, params: { id: item_id, attributes: attrs })
                     else
                       call_nested_service(definition, :create, params: { attributes: attrs })
                     end
            return result if result.failure?

            record = result.value
            parent_record.update!(foreign_key => record&.id)
            Result.success(value: record)
          end
        end
      end
    end
  end
end
