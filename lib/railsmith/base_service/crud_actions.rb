# frozen_string_literal: true

module Railsmith
  class BaseService
    # Default `create`/`update`/`destroy` action implementations.
    # @api private
    module CrudActions
      def create
        with_model_transaction do |model_klass|
          record = build_record(model_klass, sanitize_attributes(attributes_params))
          write_with_nested_support(record, write_method: :save, nested_mode: :create)
        end
      end

      def update
        with_model_transaction do |model_klass|
          record_result = find_record(model_klass, record_id)
          next record_result if record_result.failure?

          record = record_result.value
          assign_attributes(record, sanitize_attributes(attributes_params))
          write_with_nested_support(record, write_method: :save, nested_mode: :update)
        end
      end

      def destroy
        with_model_transaction do |model_klass|
          record_result = find_record(model_klass, record_id)
          next record_result if record_result.failure?

          record = record_result.value
          cascade_result = cascade_destroy_if_needed(record)
          next cascade_result if cascade_result.failure?

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

      def with_model_transaction
        model_klass = model_class
        return missing_model_class_result unless model_klass

        with_transaction(model_klass) { yield(model_klass) }
      end

      def write_with_nested_support(record, write_method:, nested_mode:)
        result = persist_write(record, method_name: write_method)
        # Use block-return (next) so with_transaction sees the failure and rolls back.
        return result if result.failure?

        return result unless nested_writes?

        nested_mode == :create ? write_nested_after_create(record) : write_nested_after_update(record)
      end

      def nested_writes?
        self.class.respond_to?(:association_registry) && self.class.association_registry.any?
      end

      def cascade_destroy_if_needed(record)
        return Result.success(value: record) unless nested_writes?

        handle_cascading_destroy(record)
      end

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
