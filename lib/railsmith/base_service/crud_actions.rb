# frozen_string_literal: true

module Railsmith
  class BaseService
    # Default `create`/`update`/`destroy` action implementations.
    # @api private
    module CrudActions
      def create
        model_klass = model_class
        return missing_model_class_result unless model_klass

        with_transaction(model_klass) do
          record = build_record(model_klass, sanitize_attributes(attributes_params))
          result = persist_write(record, method_name: :save)
          # Use block-return (next) so with_transaction sees the failure and rolls back.
          next result if result.failure?

          if self.class.respond_to?(:association_registry) && self.class.association_registry.any?
            write_nested_after_create(record)
          else
            result
          end
        end
      end

      def update
        model_klass = model_class
        return missing_model_class_result unless model_klass

        with_transaction(model_klass) do
          record_result = find_record(model_klass, record_id)
          return record_result if record_result.failure?

          record = record_result.value
          assign_attributes(record, sanitize_attributes(attributes_params))
          result = persist_write(record, method_name: :save)
          next result if result.failure?

          if self.class.respond_to?(:association_registry) && self.class.association_registry.any?
            write_nested_after_update(record)
          else
            result
          end
        end
      end

      def destroy
        model_klass = model_class
        return missing_model_class_result unless model_klass

        with_transaction(model_klass) do
          record_result = find_record(model_klass, record_id)
          return record_result if record_result.failure?

          record = record_result.value

          if self.class.respond_to?(:association_registry) && self.class.association_registry.any?
            cascade_result = handle_cascading_destroy(record)
            next cascade_result if cascade_result.failure?
          end

          persist_write(record, method_name: :destroy)
        end
      end

      def find
        model_klass = model_class
        return missing_model_class_result unless model_klass

        find_record(model_klass, record_id)
      end

      def list
        model_klass = model_class
        return missing_model_class_result unless model_klass

        Result.success(value: base_scope(model_klass).all)
      rescue StandardError => e
        Result.failure(error: map_exception_to_error(e))
      end

      private

      def persist_write(record, method_name:)
        record.public_send(method_name)

        return Result.success(value: record) if write_succeeded?(record, method_name: method_name)

        Result.failure(error: validation_error_for_record(record))
      rescue StandardError => e
        Result.failure(error: map_exception_to_error(e))
      end

      def write_succeeded?(record, method_name:)
        return record.destroyed? || record.errors.empty? if method_name == :destroy

        record.errors.empty?
      end
    end
  end
end
