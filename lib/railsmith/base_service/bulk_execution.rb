# frozen_string_literal: true

module Railsmith
  class BaseService
    # Implements bulk execution strategies (transaction modes, limits).
    # @api private
    module BulkExecution
      private

      # This project targets Ruby versions where anonymous block forwarding (`&`) may be unavailable.
      def apply_bulk_operation(model_klass, operation:, items:, transaction_mode:, &block)
        limit = bulk_limit
        return bulk_limit_exceeded_result(limit:, count: items.size) if items.size > limit

        results = apply_bulk_results(model_klass, items, transaction_mode:, &block)

        Result.success(
          value: bulk_value(operation:, items:, results:, transaction_mode:),
          meta: bulk_meta(model_klass, operation:, transaction_mode:, limit:)
        )
      end

      def apply_bulk_results(model_klass, items, transaction_mode:, &block)
        return apply_bulk_all_or_nothing(model_klass, items, &block) if transaction_mode == :all_or_nothing

        apply_bulk_best_effort(model_klass, items, &block)
      end

      def apply_bulk_best_effort(model_klass, items, &block)
        bulk_map(items) do |item|
          with_transaction(model_klass) { block.call(item) }
        end
      end

      def apply_bulk_all_or_nothing(model_klass, items, &block)
        results = nil
        transaction_wrapper(model_klass) do
          results = bulk_map(items) { |item| block.call(item) }
          rollback_transaction if results.any?(&:failure?)
        end
        results
      end

      def bulk_map(items)
        results = []
        items.each_slice(bulk_batch_size) do |slice|
          slice.each do |item|
            results << yield(item)
          end
        end
        results
      end

      def bulk_limit_exceeded_result(limit:, count:)
        Result.failure(
          error: Errors.validation_error(
            message: "Bulk limit exceeded",
            details: { limit:, count: }
          )
        )
      end
    end
  end
end
