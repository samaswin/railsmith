# frozen_string_literal: true

module Railsmith
  class BaseService
    # Default `create`/`update`/`destroy` action implementations.
    module CrudActions
      def create
        model_klass = model_class
        return missing_model_class_result unless model_klass

        with_transaction(model_klass) do
          record = build_record(model_klass, sanitize_attributes(attributes_params))
          persist_write(record, method_name: :save)
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
          persist_write(record, method_name: :save)
        end
      end

      def destroy
        model_klass = model_class
        return missing_model_class_result unless model_klass

        with_transaction(model_klass) do
          record_result = find_record(model_klass, record_id)
          return record_result if record_result.failure?

          persist_write(record_result.value, method_name: :destroy)
        end
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
