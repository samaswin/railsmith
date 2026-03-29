# frozen_string_literal: true

module Railsmith
  class BaseService
    # Defines the bulk result/value contract.
    # @api private
    module BulkContract
      private

      def bulk_value(operation:, items:, results:, transaction_mode:)
        item_payloads =
          items.zip(results).each_with_index.map do |(item, result), index|
            bulk_item_payload(item:, result:, index:)
          end

        {
          operation: operation.to_s,
          transaction_mode: transaction_mode.to_s,
          items: item_payloads,
          summary: bulk_summary(results)
        }
      end

      def bulk_item_payload(item:, result:, index:)
        {
          index:,
          input: item,
          success: result.success?,
          value: result.success? ? result.value : nil,
          error: result.failure? ? result.error.to_h : nil
        }
      end

      def bulk_summary(results)
        success_count = results.count(&:success?)
        failure_count = results.count(&:failure?)

        {
          total: results.size,
          success_count:,
          failure_count:,
          all_succeeded: failure_count.zero?
        }
      end

      def bulk_meta(model_klass, operation:, transaction_mode:, limit:)
        {
          model: model_klass.name,
          operation: operation.to_s,
          transaction_mode: transaction_mode.to_s,
          limit:
        }
      end
    end
  end
end
