# frozen_string_literal: true

module Railsmith
  class BaseService
    # Default bulk action implementations.
    module BulkActions
      include BulkParams
      include BulkExecution
      include BulkContract

      def bulk_create
        model_klass = model_class
        return missing_model_class_result unless model_klass

        bulk_write_operation(model_klass, operation: :bulk_create) do |attributes|
          record = build_record(model_klass, sanitize_attributes(attributes || {}))
          persist_write(record, method_name: :save)
        end
      end

      def bulk_update
        model_klass = model_class
        return missing_model_class_result unless model_klass

        bulk_write_operation(model_klass, operation: :bulk_update) do |item|
          bulk_update_one(model_klass, item)
        end
      end

      def bulk_destroy
        model_klass = model_class
        return missing_model_class_result unless model_klass

        bulk_write_operation(model_klass, operation: :bulk_destroy) do |item|
          bulk_destroy_one(model_klass, item)
        end
      end

      private

      # This project targets Ruby versions where anonymous block forwarding (`&`) may be unavailable.
      # rubocop:disable Style/ArgumentsForwarding
      def bulk_write_operation(model_klass, operation:, &block)
        apply_bulk_operation(
          model_klass,
          operation:,
          items: bulk_items,
          transaction_mode: bulk_transaction_mode,
          &block
        )
      end
      # rubocop:enable Style/ArgumentsForwarding

      def bulk_update_one(model_klass, item)
        id = item.is_a?(Hash) ? item[:id] : nil
        attributes = item.is_a?(Hash) ? item.fetch(:attributes, {}) : {}

        record_result = find_record(model_klass, id)
        return record_result if record_result.failure?

        record = record_result.value
        assign_attributes(record, sanitize_attributes(attributes || {}))
        persist_write(record, method_name: :save)
      end

      def bulk_destroy_one(model_klass, item)
        id = item.is_a?(Hash) ? item[:id] : item

        record_result = find_record(model_klass, id)
        return record_result if record_result.failure?

        persist_write(record_result.value, method_name: :destroy)
      end
    end
  end
end
