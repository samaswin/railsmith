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
            return false if definition.kind == :belongs_to

            nested_params_present?(source_params, definition)
          end

          def perform_nested_write(definition, parent_record, source_params, mode)
            nested_params = source_params[definition.name]
            foreign_key = definition.inferred_foreign_key(model_class)
            dispatch_nested(definition, nested_params, foreign_key, parent_record.id, mode)
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
        end
      end
    end
  end
end
