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
            if definition.kind == :belongs_to
              write_belongs_to(definition, nested_params, parent_record, mode)
            else
              foreign_key = definition.inferred_foreign_key(model_class)
              dispatch_nested(definition, nested_params, foreign_key, parent_record.id, mode)
            end
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
            if item_id
              result = call_nested_service(definition, :destroy, params: { id: item_id })
              return result if result.failure?
            end

            parent_record.update!(foreign_key => nil)
            Result.success(value: nil)
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
